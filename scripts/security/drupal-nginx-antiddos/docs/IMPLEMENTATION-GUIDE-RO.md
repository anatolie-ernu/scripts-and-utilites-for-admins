# Ghid de implementare: protecție Drupal cu nginx și Fail2Ban

Versiune: 1.1  
Data: 14 septembrie 2026  
Brand: ERNU.EU | IT & Security Solutions

## 1. Scop și arhitectură

Soluția protejează un site Drupal 10/11 pe patru niveluri:

1. `nftables` sau `iptables/ipset` limitează flood-uri de bază la L3/L4;
2. nginx limitează cererile și conexiunile la L7;
3. `security_log_processor.py` corelează semnale slabe într-un scor per IP;
4. Fail2Ban transformă alertele validate în blocări temporare în kernel.

Un atac volumetric care saturează legătura trebuie oprit de provider, CDN sau
serviciu de scrubbing. Configurația locală nu înlocuiește protecția upstream.

Fluxul implementat este:

```text
Client -> firewall L3/L4 -> nginx L7 -> Drupal/PHP-FPM
                              |
                              v
                    security-events.log
                              |
                              v
                 security_log_processor.py
                              |
                              v
                    security-alerts.log
                              |
                              v
                         Fail2Ban
                              |
                              v
                  nftables sau iptables/ipset
```

## 2. Cerințe

| Componentă | Recomandare |
|---|---|
| Drupal | 10.x sau 11.x |
| nginx | 1.22+ cu `limit_req`, `limit_conn` și `realip` |
| PHP-FPM | 8.2/8.3, preferabil socket Unix |
| Fail2Ban | 0.11+ |
| Firewall | nftables 0.9.3+ sau iptables + ipset |
| Python | 3.9+, fără pachete externe |
| Acces | root/sudo și o sesiune de recuperare separată |

## 3. Pregătire sigură

- faceți backup pentru nginx, Fail2Ban și firewall;
- păstrați o sesiune SSH separată pentru rollback;
- adăugați IP-urile de administrare/monitorizare în `ignoreip`;
- identificați proxy-urile/CDN-urile de încredere înainte de activarea real IP;
- aplicați mai întâi în staging și observați logurile cel puțin un ciclu normal.

Nu acceptați `X-Forwarded-For` de la orice sursă. `set_real_ip_from` trebuie să
conțină doar proxy-uri și intervale oficiale, actualizate.

## 4. Instalare

### 4.1 Alegeți un singur firewall

Varianta nftables, recomandată:

```bash
install -d -m 0755 /etc/nftables.d
install -m 0755 nftables/00-ddos-base.nft /etc/nftables.d/
nft -c -f /etc/nftables.d/00-ddos-base.nft
nft -f /etc/nftables.d/00-ddos-base.nft
```

Adăugați o singură dată în `/etc/nftables.conf`:

```text
include "/etc/nftables.d/*.nft"
```

Alternativa iptables/ipset:

```bash
apt-get install -y ipset iptables-persistent
bash -n iptables/00-ddos-base-iptables.sh
bash iptables/00-ddos-base-iptables.sh
netfilter-persistent save
```

### 4.2 nginx

```bash
install -m 0644 nginx/conf.d/00-security-globals.conf /etc/nginx/conf.d/
install -m 0644 nginx/sites-available/drupal-site.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/drupal-site.conf /etc/nginx/sites-enabled/
```

Activați `01-realip.conf` numai după ce ați introdus sursele proxy/CDN de
încredere. Modificați domeniul exemplu, document root, certificatul și socket-ul
PHP-FPM, apoi:

```bash
nginx -t
systemctl reload nginx
```

### 4.3 Procesorul de securitate

```bash
install -d -m 0755 /opt/drupal-antiddos/scripts
install -m 0755 scripts/security_log_processor.py /opt/drupal-antiddos/scripts/
touch /var/log/nginx/security-events.log /var/log/nginx/security-alerts.log
chown www-data:adm /var/log/nginx/security-events.log /var/log/nginx/security-alerts.log
chmod 0640 /var/log/nginx/security-events.log /var/log/nginx/security-alerts.log
install -m 0644 systemd/drupal-security-processor.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now drupal-security-processor
```

### 4.4 Fail2Ban

```bash
install -m 0644 fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/
```

Pentru nftables:

```bash
install -m 0644 fail2ban/action.d/nftables-drupal-ban.conf /etc/fail2ban/action.d/
install -m 0644 fail2ban/jail.d/drupal-nginx.local /etc/fail2ban/jail.d/
```

Pentru iptables/ipset:

```bash
install -m 0644 fail2ban/action.d/iptables-drupal-ban.conf /etc/fail2ban/action.d/
install -m 0644 fail2ban/jail.d/drupal-nginx-iptables.local \
  /etc/fail2ban/jail.d/drupal-nginx.local
```

Completați `ignoreip`, apoi validați și încărcați:

```bash
fail2ban-client -t
fail2ban-client reload
fail2ban-client status
```

## 5. Pipeline-ul de evenimente

nginx scrie numai cererile relevante în `security-events.log`. Procesorul
menține o fereastră glisantă implicită de 60 de secunde și punctează User-Agent
gol, scanere cunoscute, căi suspecte, semnături SQLi/XSS, răspunsuri 403/404,
încercări de autentificare și rate mari. La scorul 12 generează o linie
`SECURITY_ALERT` în `security-alerts.log`.

Fail2Ban citește alerta agregată cu `maxretry = 1`; blocarea este progresivă și
poate ajunge până la o săptămână pentru recidiviști. În varianta nftables,
fiecare jail folosește o tabelă proprie, astfel încât oprirea sa nu elimină
blocările altor jail-uri.

## 6. Testare controlată

```bash
python3 -m py_compile scripts/security_log_processor.py
bash -n scripts/test_attack_simulation.sh
bash -n iptables/00-ddos-base-iptables.sh
nginx -t
fail2ban-client -t
fail2ban-regex /var/log/nginx/security-alerts.log \
  /etc/fail2ban/filter.d/drupal-security-events.conf
```

Rulați simularea numai asupra unui sistem propriu de staging:

```bash
./scripts/test_attack_simulation.sh https://staging.drupal.ernu.sec
```

Confirmați cronologic evenimentul brut, alerta agregată și banul:

```bash
tail -f /var/log/nginx/security-events.log /var/log/nginx/security-alerts.log
fail2ban-client status drupal-security-events
nft list table inet f2b_drupal_critical
# sau: ipset list drupal_critical
```

## 7. Monitorizare și rollback

Comenzi uzuale:

```bash
systemctl status drupal-security-processor fail2ban nginx
journalctl -u drupal-security-processor -f
fail2ban-client status drupal-security-events
```

Pentru unban controlat:

```bash
fail2ban-client set drupal-security-events unbanip 203.0.113.7
```

Rollback: dezactivați jail-urile adăugate, reîncărcați Fail2Ban, eliminați
include-urile nginx după restaurarea backupului și restaurați regulile firewall
anterioare. Nu goliți întreg firewall-ul pe un server accesat remote.

## 8. Mentenanță

- configurați logrotate cu `create 0640 www-data adm` pentru cele două loguri;
- revizuiți trimestrial pragurile pe baza traficului real și a fals-pozitivelor;
- actualizați intervalele CDN din sursa oficială;
- monitorizați spațiul pe disc, numărul de banuri și restarturile serviciului;
- retestați după upgrade de nginx, Fail2Ban, PHP sau distribuție.

## 9. Limitări

Regulile sunt un baseline și nu sunt universale. Pragurile pot afecta NAT-uri
cu mulți utilizatori, boți legitimi, scanere autorizate, API-uri sau endpoint-uri
Drupal cu trafic intens. Testarea, observabilitatea și o cale de rollback sunt
obligatorii înainte de producție.

## 10. Documente asociate

- `CONFIGURATION-REFERENCE-RO.md` explică fiecare fișier și parametrii ajustabili;
- `OPERATIONS-RUNBOOK-RO.md` conține verificările zilnice, răspunsul la incidente și rollback-ul;
- `CHANGELOG.md` păstrează diferențele dintre versiunile publicate;
- `ERNU_EU_Ghid_Drupal_Nginx_AntiDDoS_RO.pdf` este ediția distribuibilă a acestui ghid.

## 11. Inventarul livrabilului

| Componentă | Fișier principal | Rol |
|---|---|---|
| nginx global | `nginx/conf.d/00-security-globals.conf` | zone, limite, timeouts și formate de log |
| Real IP | `nginx/conf.d/01-realip.conf` | încredere explicită pentru CDN/LB |
| Virtual host | `nginx/sites-available/drupal-site.conf` | protecție și rutare Drupal |
| Corelator | `scripts/security_log_processor.py` | scor per IP și alertă normalizată |
| Test | `scripts/test_attack_simulation.sh` | simulare confirmată numai pe staging |
| Fail2Ban | `fail2ban/filter.d`, `jail.d`, `action.d` | detecție și ban temporar |
| nftables | `nftables/00-ddos-base.nft` | baseline L3/L4 recomandat |
| iptables | `iptables/00-ddos-base-iptables.sh` | alternativă pentru sisteme legacy |
| systemd | `systemd/drupal-security-processor.service` | execuție și hardening procesor |
