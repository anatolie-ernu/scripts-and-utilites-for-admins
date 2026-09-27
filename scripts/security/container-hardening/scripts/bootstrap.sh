#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v docker >/dev/null 2>&1 || {
  echo "ERROR: docker not found." >&2
  exit 1
}

docker compose version >/dev/null 2>&1 || {
  echo "ERROR: docker compose plugin not found." >&2
  exit 1
}

mkdir -p logs

if [[ ! -f config/images.conf ]]; then
  cp config/images.conf.example config/images.conf
  echo "Created config/images.conf from example."
  echo "Review and pin the image list before scans/maintenance."
fi

echo
echo "Template prepared at: $ROOT_DIR"
echo "Next:"
echo "  sudo bash scripts/install-trivy.sh"
echo "  bash scripts/validate-template.sh"
echo "  bash scripts/scan-images.sh"
