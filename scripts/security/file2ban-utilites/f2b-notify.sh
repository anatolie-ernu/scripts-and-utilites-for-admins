#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly IP="${1:-}"
readonly JAIL="${2:-unknown}"
readonly FAILURES="${3:-unknown}"
readonly LOG_PATH="${4:-}"

readonly TO_EMAIL="${TO_EMAIL:-security@ernu.eu}"
readonly FROM_EMAIL="${FROM_EMAIL:-fail2ban@ernu.eu}"
readonly ORG_NAME="${ORG_NAME:-ERNU.EU | IT & Security Solutions}"
readonly ORG_SHORT="${ORG_SHORT:-ERNU.EU}"
readonly SENDMAIL_BIN="${SENDMAIL_BIN:-/usr/sbin/sendmail}"
readonly TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-0}"
readonly TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
readonly TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
readonly LOOKUP_TIMEOUT="${LOOKUP_TIMEOUT:-8}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

[[ -n "$IP" ]] || die "Usage: $0 <ip> <jail> <failures> <log-path>"
[[ -x "$SENDMAIL_BIN" ]] || die "sendmail interface not found: $SENDMAIL_BIN"

HOST_NAME="$(hostname -f 2>/dev/null || hostname)"
DATE_NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"
COUNTRY="Unknown"
RDNS="(no reverse DNS)"
WHOIS_SHORT="Unavailable"
LOG_LINES="No readable log path supplied."

if has_command timeout && has_command geoiplookup; then
    COUNTRY="$(timeout "$LOOKUP_TIMEOUT" geoiplookup "$IP" 2>/dev/null |
        cut -d: -f2- | sed 's/^[[:space:]]*//' | head -n 1 || true)"
    [[ -n "$COUNTRY" ]] || COUNTRY="Unknown"
fi

if has_command timeout && has_command host; then
    RDNS="$(timeout "$LOOKUP_TIMEOUT" host "$IP" 2>/dev/null |
        awk '/domain name pointer/ {gsub(/\.$/, "", $NF); print $NF; exit}' || true)"
    [[ -n "$RDNS" ]] || RDNS="(no reverse DNS)"
fi

if has_command timeout && has_command whois; then
    WHOIS_SHORT="$(timeout "$LOOKUP_TIMEOUT" whois "$IP" 2>/dev/null |
        grep -Ei '^(OrgName|Org-name|descr|country|CIDR|netname):' |
        head -n 8 || true)"
    [[ -n "$WHOIS_SHORT" ]] || WHOIS_SHORT="Unavailable"
fi

if [[ -n "$LOG_PATH" && -r "$LOG_PATH" ]]; then
    LOG_LINES="$(grep -F -- "$IP" "$LOG_PATH" 2>/dev/null | tail -n 20 || true)"
    [[ -n "$LOG_LINES" ]] || LOG_LINES="No matching log entries found."
fi

IP_HTML="$(printf '%s' "$IP" | html_escape)"
JAIL_HTML="$(printf '%s' "$JAIL" | html_escape)"
FAILURES_HTML="$(printf '%s' "$FAILURES" | html_escape)"
LOG_PATH_HTML="$(printf '%s' "${LOG_PATH:-(not supplied)}" | html_escape)"
COUNTRY_HTML="$(printf '%s' "$COUNTRY" | html_escape)"
RDNS_HTML="$(printf '%s' "$RDNS" | html_escape)"
HOST_HTML="$(printf '%s' "$HOST_NAME" | html_escape)"
WHOIS_HTML="$(printf '%s\n' "$WHOIS_SHORT" | html_escape)"
LOG_HTML="$(printf '%s\n' "$LOG_LINES" | html_escape)"
SUBJECT="[$ORG_SHORT] Fail2Ban alert - $IP banned in jail $JAIL"
BOUNDARY="f2b-$(date +%s)-$$"

{
    printf 'From: %s <%s>\n' "$ORG_NAME" "$FROM_EMAIL"
    printf 'To: %s\n' "$TO_EMAIL"
    printf 'Subject: %s\n' "$SUBJECT"
    printf 'MIME-Version: 1.0\n'
    printf 'Content-Type: multipart/alternative; boundary="%s"\n\n' "$BOUNDARY"
    printf -- '--%s\nContent-Type: text/plain; charset=UTF-8\n\n' "$BOUNDARY"
    printf '%s Fail2Ban security alert\n\n' "$ORG_NAME"
    printf 'Date: %s\nHost: %s\nJail: %s\nIP: %s\nCountry: %s\n' \
        "$DATE_NOW" "$HOST_NAME" "$JAIL" "$IP" "$COUNTRY"
    printf 'Reverse DNS: %s\nFailed attempts: %s\nLog: %s\n\n' \
        "$RDNS" "$FAILURES" "${LOG_PATH:-(not supplied)}"
    printf -- '--%s\nContent-Type: text/html; charset=UTF-8\n\n' "$BOUNDARY"
    cat <<EOF
<!doctype html>
<html lang="en"><head><meta charset="UTF-8">
<style>
body{margin:0;background:#eef2f6;color:#243b53;font-family:Arial,sans-serif}
.card{max-width:820px;margin:24px auto;background:#fff;border:1px solid #d8e2ec;border-radius:8px;overflow:hidden}
.head{padding:20px 24px;background:#102a43;color:#fff;border-bottom:4px solid #2b8eb3}
.head h1{margin:0;font-size:21px}.body{padding:22px 24px}
table{width:100%;border-collapse:collapse;margin:14px 0 20px}
th,td{padding:8px 10px;border:1px solid #d8e2ec;text-align:left;font-size:13px}
th{width:180px;background:#f5f7fa;color:#486581}
pre{padding:12px;background:#17212b;color:#e6edf3;border-radius:5px;white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}
.foot{padding:14px 24px;background:#f5f7fa;color:#627d98;font-size:11px}
</style></head><body><div class="card">
<div class="head"><h1>${ORG_NAME} - Fail2Ban Security Alert</h1></div>
<div class="body"><p>An address was automatically banned by Fail2Ban.</p>
<table>
<tr><th>Date / time</th><td>${DATE_NOW}</td></tr>
<tr><th>Host</th><td>${HOST_HTML}</td></tr>
<tr><th>Jail</th><td>${JAIL_HTML}</td></tr>
<tr><th>Banned IP</th><td><strong>${IP_HTML}</strong></td></tr>
<tr><th>Country</th><td>${COUNTRY_HTML}</td></tr>
<tr><th>Reverse DNS</th><td>${RDNS_HTML}</td></tr>
<tr><th>Failed attempts</th><td>${FAILURES_HTML}</td></tr>
<tr><th>Log path</th><td>${LOG_PATH_HTML}</td></tr>
</table>
<h3>WHOIS summary</h3><pre>${WHOIS_HTML}</pre>
<h3>Recent relevant log entries</h3><pre>${LOG_HTML}</pre>
<p>Validate whether the address belongs to a legitimate partner or trusted VPN
before changing allowlists or Fail2Ban rules.</p></div>
<div class="foot">Automated message from ${HOST_HTML}. ${ORG_NAME}.</div>
</div></body></html>
EOF
    printf '\n--%s--\n' "$BOUNDARY"
} | "$SENDMAIL_BIN" -t

if [[ "$TELEGRAM_ENABLED" == "1" ]]; then
    [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]] ||
        die "Telegram is enabled, but token or chat ID is empty"
    has_command curl || die "curl is required for Telegram notifications"

    TELEGRAM_TEXT="[$ORG_SHORT] Fail2Ban
Host: $HOST_NAME
IP: $IP
Jail: $JAIL
Country: $COUNTRY
rDNS: $RDNS
Failures: $FAILURES"

    curl --fail --silent --show-error --max-time 10 \
        --request POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${TELEGRAM_TEXT}" >/dev/null
fi
