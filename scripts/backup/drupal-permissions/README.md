# Drupal Permissions

Applies predictable ownership and permissions to a Drupal tree. The public
version requires root, validates the account and group, protects `settings.php`
by default and restores SELinux contexts when `restorecon` is available.

```bash
sudo install -m 0750 drupal-permissions.sh /usr/local/sbin/drupal-permissions
sudo DRUPAL_ROOT=/var/www/portal WEB_USER=apache WEB_GROUP=apache \
  /usr/local/sbin/drupal-permissions
```

Set `SETTINGS_WRITABLE=1` only for a controlled maintenance window. Run the
script again with the default value immediately afterward.

Copyright © 2026 ERNU.EU. All rights reserved.
