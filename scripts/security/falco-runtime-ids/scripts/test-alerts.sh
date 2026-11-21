#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

docker ps --format '{{.Names}}' | grep -qx ernu-falco || {
  echo "ERROR: ernu-falco is not running." >&2
  exit 1
}

echo "Generating benign Falco test events in disposable containers..."
echo

echo "[T1] shell in container"
docker run --rm alpine:3.22 sh -c 'echo falco-shell-test >/tmp/falco-shell-test'

echo "[T2] write below /etc in disposable container"
docker run --rm alpine:3.22 sh -c 'echo falco-test >/etc/ernu-falco-test'

echo "[T3] network utility process in container"
docker run --rm alpine:3.22 sh -c 'wget --help >/dev/null 2>&1 || true'

sleep 3

echo
echo "=== Matching ERNU alerts ==="
if [[ -f logs/events.json ]]; then
  grep -E '"rule":"ERNU |ERNU runtime alert' logs/events.json | tail -30 || true
else
  echo "events.json not found."
fi

echo
echo "Test containers were disposable and have been removed."
