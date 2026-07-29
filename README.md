# Scripts and Utilities for Admins

A public collection of practical, documented utilities for Linux, networking,
security and systems administration.

Each utility is stored in a category based on its operational purpose. Every
script has its own directory containing:

- the executable source;
- a focused README;
- detailed documentation and guides;
- sanitized examples with no production credentials or internal addresses.

Brand: **ERNU.EU | IT & Security Solutions**  
Website: [https://www.ernu.eu](https://www.ernu.eu)

## Script catalog

### Monitoring and reporting

| Utility | Description | Documentation |
|---|---|---|
| [Proxy Disk Report](scripts/monitoring/proxy-disk-report/) | Generates daily Linux disk and inode reports, shows a colored HTML report in the email body, attaches the same HTML report and delivers through Postfix. | [README](scripts/monitoring/proxy-disk-report/README.md) · [PDF guide](scripts/monitoring/proxy-disk-report/docs/ERNU_EU_Ghid_Proxy_Disk_Report_RO.pdf) |

## Repository structure

```text
scripts/
├── monitoring/
├── networking/
├── security/
├── backup/
├── mail/
└── system/
```

Categories are created as utilities are added. Each script remains isolated in
its own directory so installation instructions, rollback steps and supporting
documents stay versioned together.

## Public-data policy

All examples must be depersonalized before publication:

- use `*.ernu.sec` for technical hostnames;
- use `@ernu.eu` for example email identities;
- use RFC documentation networks such as `192.0.2.0/24`;
- never publish real passwords, API tokens, private keys, internal DNS names or
  production IP addresses.

## Copyright

Copyright © 2026 ERNU.EU. All rights reserved.

ERNU.EU | IT & Security Solutions | [www.ernu.eu](https://www.ernu.eu)
