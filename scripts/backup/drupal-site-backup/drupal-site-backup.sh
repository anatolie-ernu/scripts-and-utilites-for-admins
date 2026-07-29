#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

SITE_NAME="${SITE_NAME:-drupal-site}"
SITE_DIR="${SITE_DIR:-/var/www/drupal}"
DB_NAME="${DB_NAME:-drupal}"
MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-/root/.my.cnf}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/backup/drupal}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
EXCLUDE_WATCHDOG="${EXCLUDE_WATCHDOG:-0}"

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
HOST_SHORT="$(hostname -s)"
BACKUP_SET="${BACKUP_ROOT}/${SITE_NAME}_${HOST_SHORT}_${TIMESTAMP}"
LOG_DIR="${BACKUP_ROOT}/logs"
LOG_FILE="${LOG_DIR}/${SITE_NAME}_${TIMESTAMP}.log"
LOCK_FILE="/run/lock/backup_${SITE_NAME}.lock"

mkdir -p "$BACKUP_ROOT" "$LOG_DIR"
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "ERROR: another backup is already running." >&2; exit 1; }
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'rc=$?; ((rc == 0)) || echo "ERROR: incomplete set retained for diagnostics: $BACKUP_SET"; exit "$rc"' EXIT

for cmd in date hostname flock tee tar gzip sha256sum find df mysql mysqldump; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing command: $cmd"; exit 1; }
done

[[ -d "$SITE_DIR" ]] || { echo "ERROR: site directory not found: $SITE_DIR"; exit 1; }
[[ -r "$MYSQL_DEFAULTS_FILE" ]] || { echo "ERROR: unreadable MySQL defaults file: $MYSQL_DEFAULTS_FILE"; exit 1; }
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || { echo "ERROR: RETENTION_DAYS must be numeric."; exit 1; }
[[ "$EXCLUDE_WATCHDOG" == 0 || "$EXCLUDE_WATCHDOG" == 1 ]] ||
    { echo "ERROR: EXCLUDE_WATCHDOG must be 0 or 1."; exit 1; }

mkdir -p "$BACKUP_SET"
MYSQL=(mysql "--defaults-extra-file=${MYSQL_DEFAULTS_FILE}")
MYSQLDUMP=(mysqldump "--defaults-extra-file=${MYSQL_DEFAULTS_FILE}")

"${MYSQL[@]}" -Nse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME//\'/\'\'}';" |
    grep -Fxq "$DB_NAME" || { echo "ERROR: database is unavailable: $DB_NAME"; exit 1; }

{
    echo "Created: $(date --iso-8601=seconds)"
    echo "Server: $(hostname -f 2>/dev/null || hostname)"
    echo "Site: $SITE_DIR"
    echo "Database: $DB_NAME"
    echo "MySQL: $("${MYSQL[@]}" -Nse 'SELECT VERSION();')"
    echo "Watchdog excluded: $EXCLUDE_WATCHDOG"
} >"$BACKUP_SET/RESTORE-INFO.txt"

"${MYSQL[@]}" -Nse "SELECT TABLE_NAME,ENGINE,TABLE_ROWS FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='${DB_NAME//\'/\'\'}' ORDER BY TABLE_NAME;" \
    >"$BACKUP_SET/database-tables.tsv"

DUMP_OPTIONS=(--default-character-set=utf8 --hex-blob --routines --triggers
    --events --single-transaction --add-drop-table --databases "$DB_NAME")
(( EXCLUDE_WATCHDOG == 1 )) && DUMP_OPTIONS+=("--ignore-table=${DB_NAME}.watchdog")
"${MYSQLDUMP[@]}" "${DUMP_OPTIONS[@]}" | gzip -1 >"$BACKUP_SET/${DB_NAME}.sql.gz"
gzip -t "$BACKUP_SET/${DB_NAME}.sql.gz"
[[ -s "$BACKUP_SET/${DB_NAME}.sql.gz" ]] || { echo "ERROR: empty database dump."; exit 1; }

SITE_PARENT="$(dirname "$SITE_DIR")"
SITE_BASE="$(basename "$SITE_DIR")"
tar --acls --xattrs --selinux --numeric-owner -C "$SITE_PARENT" \
    -czf "$BACKUP_SET/${SITE_NAME}_files.tar.gz" "$SITE_BASE"
tar -tzf "$BACKUP_SET/${SITE_NAME}_files.tar.gz" >/dev/null

(
    cd "$BACKUP_SET"
    sha256sum ./*.gz ./*.txt ./*.tsv >SHA256SUMS
    sha256sum -c SHA256SUMS
)
touch "$BACKUP_SET/BACKUP-COMPLETE"

while IFS= read -r -d '' marker; do
    old_set="$(dirname "$marker")"
    [[ "$old_set" == "$BACKUP_ROOT"/"${SITE_NAME}_"* ]] && rm -rf --one-file-system "$old_set"
done < <(find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type f \
    -name BACKUP-COMPLETE -mtime "+${RETENTION_DAYS}" -print0)

find "$LOG_DIR" -type f -name "${SITE_NAME}_*.log" -mtime "+${RETENTION_DAYS}" -delete
echo "Backup completed: $BACKUP_SET"
