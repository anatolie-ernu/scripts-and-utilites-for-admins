# ERNU.EU Proxy Disk Reporting

Daily Linux disk-capacity reporting with:

- a colored HTML report displayed inline in the email;
- a plain-text fallback;
- the same HTML report as an attachment;
- filesystem and inode utilization;
- a top-level `/var` usage breakdown;
- configurable warning and critical thresholds;
- multiple recipients;
- Postfix/sendmail delivery with queueing and retry;
- cron automation and `flock` protection.

Brand: **ERNU.EU | IT & Security Solutions**  
Website: [https://www.ernu.eu](https://www.ernu.eu)

## Repository files

```text
scripts/
└── monitoring/
    └── proxy-disk-report/
        ├── proxy-disk-report.sh
        ├── README.md
        └── docs/
            └── ERNU_EU_Ghid_Proxy_Disk_Report_RO.pdf
```

## Supported systems

- Red Hat Enterprise Linux
- Rocky Linux
- AlmaLinux
- Other Linux distributions with Bash, GNU coreutils, `flock`, cron and a
  sendmail-compatible local MTA

## Dependencies

On RHEL-compatible systems:

```bash
dnf install -y postfix cronie coreutils util-linux
systemctl enable --now postfix crond
```

Verify the required commands:

```bash
command -v sendmail df du flock numfmt base64
```

## Installation

```bash
install -o root -g root -m 0750 \
  scripts/monitoring/proxy-disk-report/proxy-disk-report.sh \
  /usr/local/sbin/proxy-disk-report.sh

restorecon -v /usr/local/sbin/proxy-disk-report.sh
bash -n /usr/local/sbin/proxy-disk-report.sh
```

## Local configuration

Create `/etc/sysconfig/proxy-disk-report`:

```bash
REPORT_RECIPIENTS="admin@ernu.eu,reports@ernu.eu"
REPORT_FROM="reports@ernu.eu"
WARNING_PERCENT="80"
CRITICAL_PERCENT="90"
INCLUDE_VAR_BREAKDOWN="yes"
```

Protect it:

```bash
chown root:root /etc/sysconfig/proxy-disk-report
chmod 0600 /etc/sysconfig/proxy-disk-report
```

Never commit real recipients, internal hostnames, IP addresses, credentials or
SMTP secrets to a public repository.

## Postfix relay example

The reporting server uses a local Postfix queue and forwards mail to a trusted
relay:

```bash
postconf -e 'relayhost = [mail.ernu.sec]:25'
postconf -e 'myorigin = ernu.eu'
postconf -e 'inet_interfaces = loopback-only'
postconf -e 'smtp_tls_security_level = may'
postfix check
systemctl reload postfix
```

On the relay, authorize only the exact reporting server address:

```text
mynetworks = 127.0.0.0/8, 192.0.2.10/32, [::1]/128
smtpd_relay_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination
```

`192.0.2.10` is a documentation-only address. Replace it locally and never
authorize `0.0.0.0/0`.

## Manual test

Generate without sending:

```bash
/usr/local/sbin/proxy-disk-report.sh --dry-run
```

Send a complete report:

```bash
/usr/local/sbin/proxy-disk-report.sh
echo "Exit code: $?"
```

Verify delivery:

```bash
postqueue -p
journalctl -u postfix --since '-5 minutes' --no-pager |
  grep -iE 'relay=|status=|sent|deferred|reject'
```

## Daily cron schedule

Create `/etc/cron.d/proxy-disk-report`:

```cron
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""

0 7 * * * root /usr/local/sbin/proxy-disk-report.sh 2>&1 | /usr/bin/logger -t proxy-disk-report
```

Apply permissions:

```bash
chown root:root /etc/cron.d/proxy-disk-report
chmod 0644 /etc/cron.d/proxy-disk-report
restorecon -v /etc/cron.d/proxy-disk-report
systemctl enable --now crond
```

## Operations

```bash
# Show the mail queue
postqueue -p

# Retry all queued mail
postqueue -f

# Retry one message
postqueue -i QUEUE_ID

# Delete one confirmed message (irreversible)
postsuper -d QUEUE_ID
```

## Troubleshooting

### Relay unavailable

```bash
nc -vz -w 5 mail.ernu.sec 25
journalctl -u postfix --since '-15 minutes' --no-pager
```

### HELO or PTR rejected

```bash
hostname -f
dig +short proxy01.ernu.sec A
dig +short -x 192.0.2.10
postconf myhostname smtp_helo_name
```

### Cron did not run

```bash
systemctl status crond --no-pager
grep proxy-disk-report /var/log/cron | tail -n 20
journalctl -t proxy-disk-report --since today --no-pager
```

## Detailed guide

See:

[ERNU_EU_Ghid_Proxy_Disk_Report_RO.pdf](docs/ERNU_EU_Ghid_Proxy_Disk_Report_RO.pdf)

## Security notes

- Keep configuration files owned by `root`.
- Use mode `0600` for recipient and relay configuration.
- Permit relay by an exact `/32` address.
- Maintain forward and reverse DNS for the reporting host.
- Review report recipients because filesystem names may reveal infrastructure
  details.
- Inspect `postqueue -p` before deleting queued messages.

## Copyright

Copyright © 2026 ERNU.EU. All rights reserved.

ERNU.EU | IT & Security Solutions | [www.ernu.eu](https://www.ernu.eu)
