#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="report"
PRUNE=0
IMAGE_FILE="${IMAGE_FILE:-$ROOT_DIR/config/images.conf}"
SEVERITY="${TRIVY_MAINTENANCE_SEVERITY:-CRITICAL}"

usage() {
  cat <<EOF
Usage:
  $0 --report
  $0 --pull [--prune-dangling]

This script never recreates/restarts application containers.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) MODE="report" ;;
    --pull) MODE="pull" ;;
    --prune-dangling) PRUNE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy not found." >&2; exit 1; }
[[ -f "$IMAGE_FILE" ]] || {
  echo "ERROR: $IMAGE_FILE not found." >&2
  exit 1
}

mkdir -p logs
ts="$(date '+%Y%m%d_%H%M%S')"
log="logs/docker-image-maintenance-$ts.log"
failed=0

exec > >(tee -a "$log") 2>&1

echo "[$(date -Is)] mode=$MODE severity=$SEVERITY"
echo "Image file: $IMAGE_FILE"
echo

while IFS= read -r image || [[ -n "$image" ]]; do
  image="${image%%#*}"
  image="$(printf '%s' "$image" | xargs)"
  [[ -n "$image" ]] || continue

  echo "=== $image ==="

  if [[ "$MODE" == "pull" ]]; then
    if ! docker pull "$image"; then
      echo "ERROR: pull failed: $image"
      failed=1
      echo
      continue
    fi
  fi

  if ! trivy image       --scanners vuln       --severity "$SEVERITY"       --exit-code 1       "$image"; then
    echo "SECURITY GATE FAILED: $image has findings at severity $SEVERITY"
    failed=1
  else
    echo "SECURITY GATE PASSED: $image"
  fi

  echo
done < "$IMAGE_FILE"

if [[ "$PRUNE" -eq 1 ]]; then
  echo "Pruning dangling images only..."
  docker image prune -f
fi

echo
echo "[$(date -Is)] report=$log"

if [[ "$failed" -ne 0 ]]; then
  echo "RESULT: REVIEW REQUIRED"
  exit 1
fi

echo "RESULT: OK"
