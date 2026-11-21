#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

metadata=0
case "${1:-}" in
  --docker-metadata) metadata=1 ;;
  "") ;;
  -h|--help)
    echo "Usage: $0 [--docker-metadata]"
    exit 0
    ;;
  *)
    echo "ERROR: unknown option: $1" >&2
    exit 2
    ;;
esac

[[ -f .env ]] || cp .env.example .env
mkdir -p logs reports
chmod 0750 logs reports

bash scripts/preflight.sh
docker compose build --pull falco

if [[ "$metadata" -eq 1 ]]; then
  echo "WARNING: enabling Docker socket access for container metadata."
  docker compose -f compose.yml -f compose.docker-metadata.yml up -d falco
else
  docker compose up -d falco
fi

sleep 3
bash scripts/status.sh
