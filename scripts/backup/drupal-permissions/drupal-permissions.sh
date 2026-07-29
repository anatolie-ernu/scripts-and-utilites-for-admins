#!/usr/bin/env bash

set -Eeuo pipefail

DRUPAL_ROOT="${DRUPAL_ROOT:-/var/www/drupal}"
WEB_USER="${WEB_USER:-apache}"
WEB_GROUP="${WEB_GROUP:-$WEB_USER}"
FILES_MODE="${FILES_MODE:-2775}"
SETTINGS_WRITABLE="${SETTINGS_WRITABLE:-0}"

(( EUID == 0 )) || { echo "ERROR: run as root." >&2; exit 1; }
[[ -d "$DRUPAL_ROOT" ]] || { echo "ERROR: Drupal root not found: $DRUPAL_ROOT" >&2; exit 1; }
id "$WEB_USER" >/dev/null 2>&1 || { echo "ERROR: user not found: $WEB_USER" >&2; exit 1; }
getent group "$WEB_GROUP" >/dev/null || { echo "ERROR: group not found: $WEB_GROUP" >&2; exit 1; }
[[ "$SETTINGS_WRITABLE" == 0 || "$SETTINGS_WRITABLE" == 1 ]] ||
    { echo "ERROR: SETTINGS_WRITABLE must be 0 or 1." >&2; exit 1; }

FILES_DIR="$DRUPAL_ROOT/sites/default/files"
SETTINGS_FILE="$DRUPAL_ROOT/sites/default/settings.php"

chown -R "$WEB_USER:$WEB_GROUP" "$DRUPAL_ROOT"
find "$DRUPAL_ROOT" -type d -exec chmod 0755 {} +
find "$DRUPAL_ROOT" -type f -exec chmod 0644 {} +

install -d -o "$WEB_USER" -g "$WEB_GROUP" -m "$FILES_MODE" "$FILES_DIR"
find "$FILES_DIR" -type d -exec chmod "$FILES_MODE" {} +
find "$FILES_DIR" -type f -exec chmod 0664 {} +

if [[ -f "$SETTINGS_FILE" ]]; then
    if [[ "$SETTINGS_WRITABLE" == 1 ]]; then
        chmod 0664 "$SETTINGS_FILE"
        echo "WARNING: settings.php is writable; return SETTINGS_WRITABLE to 0 after maintenance."
    else
        chmod 0440 "$SETTINGS_FILE"
    fi
fi

command -v restorecon >/dev/null 2>&1 && restorecon -RF "$DRUPAL_ROOT" || true
echo "Drupal permissions updated: $DRUPAL_ROOT"
