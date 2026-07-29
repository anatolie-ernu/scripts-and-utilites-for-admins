# Drupal Site Backup

Creates a timestamped backup set containing a compressed MySQL/MariaDB dump,
the Drupal document root, restore metadata, table inventory and SHA-256 checksums.
Only complete sets marked `BACKUP-COMPLETE` are removed by retention.

## Quick start

```bash
sudo install -m 0750 drupal-site-backup.sh /usr/local/sbin/drupal-site-backup
sudo SITE_NAME=portal SITE_DIR=/var/www/portal DB_NAME=portal \
  BACKUP_ROOT=/srv/backup/drupal /usr/local/sbin/drupal-site-backup
```

Store database credentials in `/root/.my.cnf` with mode `0600`. Test restoration
regularly; a successful backup command alone does not prove recoverability.

## Main variables

`SITE_NAME`, `SITE_DIR`, `DB_NAME`, `MYSQL_DEFAULTS_FILE`, `BACKUP_ROOT`,
`RETENTION_DAYS` and `EXCLUDE_WATCHDOG`.

Copyright © 2026 ERNU.EU. All rights reserved.
