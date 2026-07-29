# Fail2Ban Utilities

Operational Bash utilities for Fail2Ban administration and security alerts.

## Included utilities

### `unban-fail2ban.sh`

- lists every active jail and its banned IP addresses;
- removes one IPv4 or IPv6 address from all active jails;
- removes all bans only after typing the exact confirmation `UNBAN-ALL`;
- verifies root privileges and Fail2Ban connectivity before opening the menu;
- contains no environment-specific hostnames, credentials or IP addresses.

### `f2b-notify.sh`

- sends a multipart plain-text and styled HTML email for every ban event;
- optionally delivers a Telegram notification;
- enriches alerts with GeoIP, reverse DNS and a short WHOIS summary;
- reads recipients, sender identity and Telegram secrets from environment
  variables;
- applies timeouts and HTML escaping to external data.

## Installation

```bash
sudo install -m 0750 unban-fail2ban.sh /usr/local/sbin/unban-fail2ban
sudo /usr/local/sbin/unban-fail2ban

sudo install -m 0750 f2b-notify.sh /usr/local/sbin/f2b-notify
```

The default client path is `/usr/bin/fail2ban-client`. Override it when needed:

```bash
sudo FAIL2BAN_CLIENT=/usr/local/bin/fail2ban-client \
  /usr/local/sbin/unban-fail2ban
```

See the PDF guide for a Fail2Ban action configuration example.

## Requirements

- Bash 4 or newer;
- an active Fail2Ban service;
- root privileges;
- interactive terminal.

The notification utility additionally uses `/usr/sbin/sendmail`; `curl`,
`geoiplookup`, `host` and `whois` are optional enrichment tools.

## Safety

Unbanning an address changes the live firewall protection state immediately.
Record the reason and incident/ticket reference before removing a ban. Option 3
removes all active bans and should only be used during a controlled recovery.

## Documentation

[ERNU.EU Romanian PDF guide](docs/ERNU_EU_Ghid_Fail2Ban_Utilities_RO.pdf)

## Copyright

Copyright © 2026 ERNU.EU. All rights reserved.

ERNU.EU | IT & Security Solutions | [www.ernu.eu](https://www.ernu.eu)
