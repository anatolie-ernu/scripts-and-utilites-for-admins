#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

new="${1:-}"
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Usage: $0 <falco-version>   e.g. 0.45.2" >&2
  exit 2
}

python3 - "$new" <<'PY'
from pathlib import Path
import re, sys
v=sys.argv[1]
for name in [".env.example","Dockerfile","compose.yml"]:
    p=Path(name)
    s=p.read_text()
    s=re.sub(r'(?<![0-9])0\.45\.2(?![0-9])',v,s)
    p.write_text(s)
print(f"Updated Falco template version to {v}")
PY

echo "Review upstream release notes before commit/deploy."
