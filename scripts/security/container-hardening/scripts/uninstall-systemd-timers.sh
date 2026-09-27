#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "ERROR: run as root." >&2; exit 1; }

units=(
  ernu-docker-image-maintenance.timer
  ernu-docker-image-maintenance.service
  ernu-docker-bench.timer
  ernu-docker-bench.service
)

for unit in "${units[@]}"; do
  systemctl disable --now "$unit" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/$unit"
  echo "Removed $unit"
done

systemctl daemon-reload
systemctl reset-failed
