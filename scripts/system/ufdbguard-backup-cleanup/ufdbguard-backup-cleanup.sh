#!/usr/bin/env bash
set -Eeuo pipefail

BASE='/var/lib/ufdbguard'
ACTIVE="$BASE/blacklists"
KEEP=3
LOCK='/run/ufdbguard-backup-cleanup.lock'
MODE="${1:-}"

log() { printf '%s [ufdb-cleanup] %s\n' "$(date '+%F %T')" "$*"; }

[[ -z "$MODE" || "$MODE" == '--dry-run' ]] || {
  log "Argument invalid: $MODE"; exit 2;
}

exec 9>"$LOCK"
flock -n 9 || { log 'Alta curatare ruleaza; iesire.'; exit 0; }

[[ -d "$BASE" && ! -L "$BASE" ]] || { log 'BASE invalid'; exit 1; }
[[ -d "$ACTIVE" && ! -L "$ACTIVE" ]] || { log 'Lista activa lipseste'; exit 1; }
[[ "$(findmnt -n -o TARGET -T "$BASE")" == '/var' ]] || {
  log 'Mount neasteptat pentru directorul de date'; exit 1;
}
for svc in squid ufdbguard; do
  systemctl is-active --quiet "$svc" || {
    log "Serviciu inactiv: $svc; nu sterg nimic"; exit 1;
  }
done

# Detectie suplimentara, nu substituie lock comun cu updater-ul.
if pgrep -f '[/]etc/ufdbguard/scripts/20-fetch-ut1\.sh' >/dev/null; then
  log 'Updater detectat; curatare amanata.'; exit 0
fi

mapfile -d '' BACKUPS < <(
  find "$BASE" -mindepth 1 -maxdepth 1 -type d \
    -name 'blacklists.bak.*' -print0 | LC_ALL=C sort -z
)
VALID=()
for dir in "${BACKUPS[@]}"; do
  name="${dir##*/}"
  [[ "$name" =~ ^blacklists\.bak\.[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]] || continue
  [[ ! -L "$dir" ]] || continue
  VALID+=("$dir")
done

count=${#VALID[@]}
log "Backupuri valide: $count; retentie: $KEEP; mod: ${MODE:-real}"
(( count > KEEP )) || { log 'Nimic de eliminat'; exit 0; }

df -h "$BASE"
delete_count=$((count - KEEP))
log 'Backupuri protejate (ultimele 3):'
printf '  %s\n' "${VALID[@]:delete_count}"

for (( i=0; i<delete_count; i++ )); do
  dir="${VALID[$i]}"
  [[ "$dir" == "$BASE"/blacklists.bak.* && -d "$dir" && ! -L "$dir" ]] || exit 1
  # Protectie daca directorul a fost modificat in ultimele 3 ore.
  if find "$dir" -maxdepth 0 -mmin -180 -print -quit | grep -q .; then
    log "OMIS (recent): $dir"; continue
  fi
  if [[ "$MODE" == '--dry-run' ]]; then
    log "SIMULARE: $dir"
  else
    log "STERG: $dir"
    rm -rf --one-file-system -- "$dir"
  fi
done
log 'Verificare finala:'
df -h "$BASE"
systemctl is-active squid ufdbguard
