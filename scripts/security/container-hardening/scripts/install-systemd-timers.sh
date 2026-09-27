#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: run as root." >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR=/etc/systemd/system

[[ -f "$ROOT_DIR/config/images.conf" ]] || {
  cp "$ROOT_DIR/config/images.conf.example" "$ROOT_DIR/config/images.conf"
  echo "Created $ROOT_DIR/config/images.conf from example."
  echo "Review image tags before the first scheduled run."
}

for unit in "$ROOT_DIR"/systemd/*.service "$ROOT_DIR"/systemd/*.timer; do
  name="$(basename "$unit")"
  sed "s|@ROOT_DIR@|$ROOT_DIR|g" "$unit" > "$UNIT_DIR/$name"
  chmod 0644 "$UNIT_DIR/$name"
  echo "Installed $UNIT_DIR/$name"
done

systemctl daemon-reload
systemctl enable --now ernu-docker-image-maintenance.timer
systemctl enable --now ernu-docker-bench.timer

echo
systemctl list-timers 'ernu-docker-*'
