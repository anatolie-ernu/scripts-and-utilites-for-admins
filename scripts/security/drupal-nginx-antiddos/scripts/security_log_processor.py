#!/usr/bin/env python3
"""
security_log_processor.py
==============================================================================
Proceseaza in timp real logul custom "security" generat de nginx
(/var/log/nginx/security-events.log, definit in 00-security-globals.conf)
si genereaza alerte agregate pe care fail2ban le poate actiona.

DE CE EXISTA ACEST SCRIPT (nu doar filtre fail2ban direct pe access.log)
------------------------------------------------------------------------
Fail2ban stie sa faca UN singur lucru bine: sa numere de cate ori o LINIE
individuala se potriveste cu un regex, intr-o fereastra de timp, si sa
actioneze la depasirea unui prag. Nu poate:
  - corela mai multe semnale SLABE (un 404, apoi un User-Agent gol, apoi o
    cerere spre /user/login, toate de la acelasi IP in 30 de secunde) intr-un
    semnal PUTERNIC de atac;
  - mentine un scor / stare per-IP intre cereri de tipuri diferite;
  - aplica logica de business (ex: "ignora POST catre /user/login daca
    body-ul contine un token CSRF valid").

Acest script joaca rolul unui corelator IDS minimal:
  nginx (access + security log)
        -> security_log_processor.py (parsare + scoring + corelare)
        -> security-alerts.log (linii normalizate SECURITY_ALERT)
        -> fail2ban (regex simplu, maxretry=1, pentru ca scorul e deja facut)
        -> nftables (blocare la nivel de kernel, inainte sa ajunga la nginx)

FORMAT LINIE SURSA (log_format security din nginx):
2026-09-14T10:22:31+03:00 client=203.0.113.7 method=GET uri="/wp-login.php"
  status=404 bytes=162 reqtime=0.002 ua="" ref="-" bot=1 probe=1 xff="-"

FORMAT LINIE DE IESIRE (consumata de filter.d/drupal-security-events.conf):
2026-09-14T10:22:45+0300 SECURITY_ALERT ip=203.0.113.7 score=12
  reason=bot_ua,path_probe,login_bruteforce path=/user/login count=6 window=60s
"""

import re
import sys
import time
import signal
import argparse
import logging
from collections import defaultdict, deque
from dataclasses import dataclass, field

LOG_LINE_RE = re.compile(
    r'^(?P<time>\S+)\s+client=(?P<ip>\S+)\s+method=(?P<method>\S+)\s+'
    r'uri="(?P<uri>[^"]*)"\s+status=(?P<status>\d+)\s+bytes=(?P<bytes>\d+)\s+'
    r'reqtime=(?P<reqtime>[\d.]+)\s+ua="(?P<ua>[^"]*)"\s+ref="(?P<ref>[^"]*)"\s+'
    r'bot=(?P<bot>\d)\s+probe=(?P<probe>\d)\s+xff="(?P<xff>[^"]*)"'
)

# ------------------------------------------------------------------------
# REGULI DE SCOR -- fiecare semnal slab primeste o pondere.
# Pragul de alerta e comparat cu SUMA scorurilor dintr-o fereastra glisanta.
# ------------------------------------------------------------------------
SCORE_RULES = {
    "empty_user_agent":    3,   # UA gol -- foarte rar la trafic legitim de browser
    "known_bad_bot":       6,   # UA de scanner cunoscut (nikto, sqlmap etc)
    "path_probe":          4,   # cale tipica de scanare (wp-admin, .env, .git...)
    "sqli_xss_signature":  8,   # semnatura SQLi/XSS in URI
    "status_404_burst":    1,   # fiecare 404 individual e slab, dar se aduna
    "status_403_repeat":   5,   # 403 repetat -- de obicei bruteforce/ACL probing
    "login_endpoint_hit":  2,   # orice hit pe /user/login se puncteaza usor
    "login_bruteforce":   10,   # >=5 hit-uri pe /user/login in fereastra
    "high_request_rate":   7,   # >20 cereri/10s de la acelasi IP
}

ALERT_THRESHOLD = 12     # scor cumulat care declanseaza un SECURITY_ALERT
WINDOW_SECONDS = 60      # fereastra glisanta pentru corelare per-IP
COOLDOWN_SECONDS = 300   # nu retrimite alerta pentru acelasi IP mai des de atat


@dataclass
class IPState:
    events: deque = field(default_factory=deque)   # (timestamp, score, reason)
    request_times: deque = field(default_factory=deque)
    login_hits: deque = field(default_factory=deque)
    last_alert: float = 0.0


class Correlator:
    def __init__(self, threshold=ALERT_THRESHOLD, window=WINDOW_SECONDS,
                 cooldown=COOLDOWN_SECONDS):
        self.state = defaultdict(IPState)
        self.threshold = threshold
        self.window = window
        self.cooldown = cooldown

    def _prune(self, dq, now):
        while dq and now - dq[0][0] > self.window:
            dq.popleft()

    def ingest(self, fields, now):
        """Aplica regulile de scor pentru o linie parsata; intoarce alerta sau None."""
        ip = fields["ip"]
        st = self.state[ip]
        reasons = []

        st.request_times.append(now)
        self._prune_simple(st.request_times, now)

        if fields["ua"] == "":
            reasons.append(("empty_user_agent", SCORE_RULES["empty_user_agent"]))
        if fields["bot"] == "1":
            reasons.append(("known_bad_bot", SCORE_RULES["known_bad_bot"]))
        if fields["probe"] == "1":
            reasons.append(("path_probe", SCORE_RULES["path_probe"]))
        if re.search(r"(union|select|sleep\(|<script|\.\./)", fields["uri"], re.I):
            reasons.append(("sqli_xss_signature", SCORE_RULES["sqli_xss_signature"]))
        if fields["status"] == "404":
            reasons.append(("status_404_burst", SCORE_RULES["status_404_burst"]))
        if fields["status"] == "403":
            reasons.append(("status_403_repeat", SCORE_RULES["status_403_repeat"]))

        if "/user/login" in fields["uri"]:
            reasons.append(("login_endpoint_hit", SCORE_RULES["login_endpoint_hit"]))
            st.login_hits.append(now)
            self._prune_simple(st.login_hits, now)
            if len(st.login_hits) >= 5:
                reasons.append(("login_bruteforce", SCORE_RULES["login_bruteforce"]))

        if len(st.request_times) >= 20 and (now - st.request_times[0]) <= 10:
            reasons.append(("high_request_rate", SCORE_RULES["high_request_rate"]))

        if not reasons:
            return None

        for name, score in reasons:
            st.events.append((now, score, name))
        self._prune(st.events, now)

        total_score = sum(s for _, s, _ in st.events)
        if total_score < self.threshold:
            return None
        if now - st.last_alert < self.cooldown:
            return None  # deja alertat recent pentru acest IP, evitam spam-ul

        st.last_alert = now
        unique_reasons = sorted({name for _, _, name in st.events})
        return {
            "ip": ip,
            "score": total_score,
            "reasons": unique_reasons,
            "path": fields["uri"],
            "count": len(st.events),
        }

    def _prune_simple(self, dq, now):
        while dq and now - dq[0] > self.window:
            dq.popleft()


def follow(path):
    """Tail -F: urmareste fisierul si detecteaza rotatia (inode nou)."""
    fh = open(path, "r")
    fh.seek(0, 2)  # sarim la finalul fisierului existent
    inode = None
    try:
        import os
        inode = os.fstat(fh.fileno()).st_ino
    except Exception:
        pass

    while True:
        line = fh.readline()
        if line:
            yield line
            continue

        time.sleep(0.5)
        try:
            import os
            current_inode = os.stat(path).st_ino
            if inode is not None and current_inode != inode:
                fh.close()
                fh = open(path, "r")
                inode = current_inode
        except FileNotFoundError:
            continue


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--log-path", default="/var/log/nginx/security-events.log",
                     help="Log-ul custom 'security' scris de nginx (INTRARE)")
    ap.add_argument("--output-path", default="/var/log/nginx/security-alerts.log",
                     help="Fisierul cu alerte normalizate citit de fail2ban (IESIRE)")
    ap.add_argument("--threshold", type=int, default=ALERT_THRESHOLD)
    ap.add_argument("--window", type=int, default=WINDOW_SECONDS)
    args = ap.parse_args()

    logging.basicConfig(level=logging.INFO,
                         format="%(asctime)s processor: %(message)s")

    correlator = Correlator(threshold=args.threshold, window=args.window)
    out_fh = open(args.output_path, "a", buffering=1)  # line-buffered

    def handle_sigterm(signum, frame):
        logging.info("Oprire la semnal %s", signum)
        out_fh.close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_sigterm)
    signal.signal(signal.SIGINT, handle_sigterm)

    logging.info("Pornit. Citesc din %s, scriu alerte in %s",
                 args.log_path, args.output_path)

    for raw_line in follow(args.log_path):
        m = LOG_LINE_RE.match(raw_line.strip())
        if not m:
            continue
        fields = m.groupdict()
        now = time.time()
        alert = correlator.ingest(fields, now)
        if alert:
            ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            line = (f"{ts} SECURITY_ALERT ip={alert['ip']} "
                    f"score={alert['score']} reason={','.join(alert['reasons'])} "
                    f"path={alert['path']} count={alert['count']} "
                    f"window={args.window}s\n")
            out_fh.write(line)
            logging.warning("ALERTA: %s", line.strip())


if __name__ == "__main__":
    main()
