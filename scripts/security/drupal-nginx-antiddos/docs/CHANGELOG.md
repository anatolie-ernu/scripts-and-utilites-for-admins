# Changelog

## 1.1 - 2026-09-14

- integrare publică și sanitizată în catalogul repository-ului;
- adăugare ghid Markdown, referință de configurare și runbook operațional;
- sincronizare PDF cu documentația curentă;
- corectare regex Fail2Ban pentru timestamp-ul nginx `error.log`;
- izolare nftables per jail, pentru a evita ștergerea regulilor altor jail-uri;
- folosire de identificatori nftables compatibili, cu `_`;
- limitare SYN per IP sursă în locul unui prag global;
- validare HTTPS și confirmare explicită `STAGING` în scriptul de simulare;
- înlocuire exemple locale cu domenii și rețele rezervate documentației.

## 1.0 - 2026-09-14

- versiunea inițială a pachetului nginx, procesor Python, Fail2Ban,
  nftables/iptables și serviciu systemd.
