#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[validate] shell syntax"
for f in scripts/*.sh; do
  bash -n "$f"
done

echo "[validate] compose hardening example"
docker compose -f examples/compose.hardening.example.yml config --quiet

echo "[validate] compose hardening policy checker"
bash scripts/check-compose-hardening.sh examples/compose.hardening.example.yml

echo "[validate] configuration examples"
python3 -m json.tool examples/daemon.userns-remap.example.json >/dev/null

echo "[validate] OK"
