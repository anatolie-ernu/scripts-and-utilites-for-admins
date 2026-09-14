# Runbook operațional și rollback

Versiune: 1.1 - 14 septembrie 2026

## Verificare după deployment

```bash
systemctl is-active nginx fail2ban drupal-security-processor
nginx -t
fail2ban-client -t
fail2ban-client status
tail -n 20 /var/log/nginx/security-events.log
tail -n 20 /var/log/nginx/security-alerts.log
```

Pentru nftables:

```bash
nft list tables
nft list table inet f2b_drupal_critical
```

Pentru iptables/ipset:

```bash
iptables -S INPUT
ipset list drupal_critical
```

## Verificare periodică

Zilnic:

- starea celor trei servicii;
- rata răspunsurilor 429/403/404;
- IP-urile banate și fals-pozitivele raportate;
- spațiul disponibil pentru loguri.

Săptămânal:

- restarturi neașteptate ale procesorului;
- top motive/scoruri din `security-alerts.log`;
- schimbări de trafic și endpoint-uri noi.

Trimestrial:

- pragurile nginx și `SCORE_RULES`;
- lista `ignoreip`;
- intervalele oficiale CDN/LB;
- testul complet pe staging și procedura de rollback.

## Răspuns la blocarea unui utilizator legitim

1. identificați jail-ul și IP-ul din `fail2ban-client status`;
2. validați că IP-ul aparține utilizatorului/proxy-ului legitim;
3. păstrați logurile relevante pentru analiză;
4. executați unban numai în jail-ul corect;
5. ajustați cauza, nu adăugați automat intervale mari în allowlist.

```bash
fail2ban-client set drupal-security-events unbanip 203.0.113.7
```

## Procesorul nu generează alerte

```bash
systemctl status drupal-security-processor
journalctl -u drupal-security-processor --since "30 minutes ago"
ls -l /var/log/nginx/security-events.log /var/log/nginx/security-alerts.log
```

Verificați: formatul logului nginx, permisiunile, existența evenimentelor
relevante, rotația logurilor și pragul de scor.

## Fail2Ban nu banează

```bash
fail2ban-client -t
fail2ban-regex /var/log/nginx/security-alerts.log \
  /etc/fail2ban/filter.d/drupal-security-events.conf
fail2ban-client status drupal-security-events
```

Verificați acțiunea firewall selectată și faptul că nu sunt instalate simultan
ambele variante de jail.

## Rollback controlat

Mențineți o sesiune administrativă separată. Nu executați flush global asupra
firewall-ului unui server accesat de la distanță.

1. dezactivați numai jail-urile adăugate de acest pachet;
2. reîncărcați Fail2Ban și confirmați jail-urile rămase;
3. opriți și dezactivați `drupal-security-processor`;
4. restaurați configurația nginx din backup, validați și reîncărcați;
5. eliminați doar tabela/seturile create de pachet;
6. restaurați politica firewall anterioară și verificați accesul.

Comenzi orientative:

```bash
systemctl disable --now drupal-security-processor
nginx -t && systemctl reload nginx
systemctl reload fail2ban
```

Documentați ora, cauza, comenzile executate și rezultatul fiecărui rollback.

## Evidențe pentru incident

Păstrați, în conformitate cu politica organizației:

- timestamp și fus orar;
- IP-ul și jail-ul;
- liniile relevante din ambele loguri de securitate;
- scorul și motivele corelatorului;
- regula/setul firewall;
- modificările de configurare și aprobările asociate.

Sanitizați datele înainte de distribuire publică.
