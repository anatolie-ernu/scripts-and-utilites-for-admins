#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for file in scripts/*.sh; do
  bash -n "$file"
done

[[ -f .env ]] || cp .env.example .env

docker compose config --quiet
docker compose -f compose.yml -f compose.docker-metadata.yml config --quiet

echo "[validate] building pinned Falco image"
docker compose build --pull falco

echo "[validate] validating Falco configuration/rules"
docker compose run --rm --no-deps falco --dry-run

echo "[validate] OK"
