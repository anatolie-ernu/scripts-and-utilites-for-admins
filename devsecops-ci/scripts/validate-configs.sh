#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - <<'PY' "$root_dir"
import pathlib, sys
import yaml
root = pathlib.Path(sys.argv[1])
for path in root.rglob("*.yml"):
    with path.open(encoding="utf-8") as handle:
        yaml.safe_load(handle)
    print(f"YAML OK: {path.relative_to(root)}")
PY

docker compose --env-file "$root_dir/platform/sonarqube/.env.example" \
  -f "$root_dir/platform/sonarqube/docker-compose.yml" config --quiet
echo "Compose OK"

