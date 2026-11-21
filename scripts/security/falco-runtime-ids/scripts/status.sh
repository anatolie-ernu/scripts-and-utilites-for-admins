#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== Container ==="
docker ps -a --filter name='^/ernu-falco$'   --format 'table {{.Names}}	{{.Image}}	{{.Status}}'

echo
echo "=== Falco version ==="
docker exec ernu-falco falco --version 2>/dev/null || true

echo
echo "=== Recent container logs ==="
docker logs --tail 30 ernu-falco 2>&1 || true

echo
echo "=== Event file ==="
if [[ -f logs/events.json ]]; then
  ls -lh logs/events.json
  tail -5 logs/events.json
else
  echo "No events.json yet."
fi
