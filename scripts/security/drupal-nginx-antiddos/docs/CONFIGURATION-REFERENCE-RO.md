# Referință de configurare

Versiune: 1.1 - 14 septembrie 2026

## nginx

### `00-security-globals.conf`

| Parametru | Valoare implicită | Ajustare recomandată |
|---|---:|---|
| `general` | 10 cereri/s | trafic web obișnuit |
| `login` | 2 cereri/s | autentificare și resetare parolă |
| `api` | 30 cereri/s | JSON:API/REST; măsurați înainte de reducere |
| `cron` | 1 cerere/minut | endpoint Drupal cron |
| `perip` | 20 conexiuni | atenție la utilizatorii din spatele NAT |
| `perserver` | 2.000 conexiuni | corelați cu workers, RAM și upstream |
| `client_max_body_size` | 8 MiB | măriți numai pentru upload-uri necesare |

`$binary_remote_addr` trebuie să reprezinte clientul real. Dacă există CDN/LB,
activați `01-realip.conf` numai cu intervalele oficiale ale proxy-urilor de
încredere. Nu permiteți arbitrar `X-Forwarded-For`.

### `drupal-site.conf`

Înlocuiți obligatoriu:

- `server_name drupal.ernu.sec`;
- document root `/var/www/drupal/web`;
- căile certificatului TLS;
- socket-ul `/run/php/php8.3-fpm.sock`;
- IP-urile autorizate pentru `install.php` și `update.php`.

Configurația blochează dotfiles, PHP în directoarele de upload, directoare
vendor și fișierele de proiect expuse accidental. Verificați compatibilitatea
cu modulele Drupal și rutele API folosite de aplicație.

## Corelatorul Python

| Parametru | Implicit | Semnificație |
|---|---:|---|
| `ALERT_THRESHOLD` | 12 | scorul minim pentru alertă |
| `WINDOW_SECONDS` | 60 | fereastra de corelare |
| `COOLDOWN_SECONDS` | 300 | interval minim între alerte pentru același IP |
| `--log-path` | `security-events.log` | intrarea produsă de nginx |
| `--output-path` | `security-alerts.log` | ieșirea citită de Fail2Ban |

Modificarea ponderilor din `SCORE_RULES` trebuie justificată cu exemple din
loguri sanitizate. O reducere prea agresivă poate bloca utilizatori legitimi.

## Fail2Ban

| Jail | `maxretry` | `findtime` | `bantime` |
|---|---:|---:|---:|
| `nginx-limit-req` | 15 | 60 s | 1 h |
| `nginx-botsearch` | 5 | 300 s | 6 h |
| `drupal-security-events` | 1 | 120 s | 24 h |

`maxretry = 1` este intenționat pentru alerta agregată: pragul și corelarea au
fost deja aplicate de procesor. Completați `ignoreip` cu adresele reale de
administrare, VPN și monitorizare, fără intervale excesiv de largi.

Numele interne ale seturilor folosesc `_` (`nginx_limit`, `nginx_bots`,
`drupal_critical`) pentru compatibilitate cu identificatorii nftables.

## Firewall

Alegeți o singură variantă:

- nftables: tabele izolate `f2b_<name>` pentru fiecare jail;
- iptables/ipset: set IPv4 și IPv6 separat pentru fiecare jail.

Regulile de bază limitează per IP rata SYN, ICMP și conexiunile noi către
80/443. Pragurile sunt baseline-uri, nu valori universale. Nu înlocuiți politica
firewall existentă fără analizarea ordinii hook-urilor și lanțurilor.

## Permisiuni și logrotate

Procesorul rulează ca `www-data:adm`, cu `ProtectSystem=strict` și drept de
scriere numai în `/var/log/nginx`. Configurația logrotate trebuie să recreeze:

```text
create 0640 www-data adm
```

După orice modificare validați în această ordine:

```bash
python3 -m py_compile scripts/security_log_processor.py
bash -n scripts/test_attack_simulation.sh
bash -n iptables/00-ddos-base-iptables.sh
nft -c -f nftables/00-ddos-base.nft
nginx -t
fail2ban-client -t
```
