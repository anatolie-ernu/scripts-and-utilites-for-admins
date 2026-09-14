# Drupal + nginx anti-DDoS / anti-bruteforce

Pachet public si sanitizat pentru protectia Drupal 10/11 prin nginx rate
limiting, corelarea evenimentelor de securitate, Fail2Ban si firewall.

Documentatie:

- [Ghid complet de implementare (RO)](docs/IMPLEMENTATION-GUIDE-RO.md)
- [Referință de configurare (RO)](docs/CONFIGURATION-REFERENCE-RO.md)
- [Runbook operațional și rollback (RO)](docs/OPERATIONS-RUNBOOK-RO.md)
- [Istoricul versiunilor](docs/CHANGELOG.md)
- [Ghid PDF (RO)](docs/ERNU_EU_Ghid_Drupal_Nginx_AntiDDoS_RO.pdf)

Documentația Markdown și PDF-ul sunt sincronizate la versiunea 1.1.

> [!CAUTION]
> Aceasta protectie reduce abuzul L7 si unele flood-uri L3/L4 locale, dar nu
> poate absorbi un atac volumetric care depaseste conexiunea serverului.
> Pentru acesta este necesara protectie upstream/CDN/scrubbing.

## Doua variante de firewall -- alegeti UNA

Pachetul include doua implementari echivalente pentru blocarea efectiva a
IP-urilor: **nftables** (recomandat, mai modern) si **iptables + ipset**
(pentru sisteme fara suport nftables). Alegeti o singura varianta -- nu
instalati fisierele ambelor variante simultan, ar duplica banurile.

## Structura

```
nginx/
  conf.d/00-security-globals.conf   -> /etc/nginx/conf.d/
  conf.d/01-realip.conf              -> /etc/nginx/conf.d/ (doar daca aveti CDN/LB in fata)
  sites-available/drupal-site.conf   -> /etc/nginx/sites-available/ (+ symlink in sites-enabled/)

fail2ban/
  filter.d/*.conf                    -> /etc/fail2ban/filter.d/ (identice pentru ambele variante)
  jail.d/drupal-nginx.local          -> /etc/fail2ban/jail.d/  [varianta NFTABLES]
  jail.d/drupal-nginx-iptables.local -> /etc/fail2ban/jail.d/  [varianta IPTABLES -- redenumiti in drupal-nginx.local]
  action.d/nftables-drupal-ban.conf  -> /etc/fail2ban/action.d/ [varianta NFTABLES]
  action.d/iptables-drupal-ban.conf  -> /etc/fail2ban/action.d/ [varianta IPTABLES]

scripts/
  security_log_processor.py          -> /opt/drupal-antiddos/scripts/
  test_attack_simulation.sh          -> pentru testare pe staging

systemd/
  drupal-security-processor.service  -> /etc/systemd/system/

nftables/
  00-ddos-base.nft                   -> /etc/nftables.d/ [varianta NFTABLES]

iptables/
  00-ddos-base-iptables.sh           -> rulare directa + netfilter-persistent save [varianta IPTABLES]
```

## Ordine de instalare (rezumat -- detalii în ghid)

1. Nivel retea: `nft -f nftables/00-ddos-base.nft` **SAU**
   `bash iptables/00-ddos-base-iptables.sh && netfilter-persistent save`
2. Copiati fisierele nginx, `nginx -t`, `systemctl reload nginx`
3. `mkdir -p /opt/drupal-antiddos/scripts && cp scripts/security_log_processor.py ...`
4. `cp systemd/*.service /etc/systemd/system/ && systemctl enable --now drupal-security-processor`
5. Copiati filtrele fail2ban (comune), apoi:
   - varianta nftables: `jail.d/drupal-nginx.local` + `action.d/nftables-drupal-ban.conf`
   - varianta iptables: `apt install ipset iptables-persistent`, apoi
     `jail.d/drupal-nginx-iptables.local` (redenumit `drupal-nginx.local`) +
     `action.d/iptables-drupal-ban.conf`
   - `fail2ban-client reload`
6. Validati configuratia si testati cu `scripts/test_attack_simulation.sh`
   exclusiv pe un mediu propriu de staging.

## Validare rapida

```bash
nginx -t
fail2ban-client -t
python3 -m py_compile scripts/security_log_processor.py
bash -n scripts/test_attack_simulation.sh
bash -n iptables/00-ddos-base-iptables.sh
```

Inainte de activare, completati `server_name`, document root, certificatul,
socket-ul PHP-FPM, proxy-urile de incredere si `ignoreip`. Nu rulati simultan
variantele nftables si iptables/ipset.

## Licenta si utilizare

Configuratiile sunt exemple operationale si trebuie adaptate/testate pe
staging. Utilizatorul ramane responsabil pentru praguri, allowlist-uri,
backup, acces de urgenta si compatibilitatea cu firewall-ul existent.
