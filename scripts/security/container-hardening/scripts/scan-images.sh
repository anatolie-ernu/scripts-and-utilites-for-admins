#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v trivy >/dev/null 2>&1 || {
  echo "ERROR: trivy not found. Run sudo ./scripts/install-trivy.sh" >&2
  exit 1
}

IMAGE_FILE="${IMAGE_FILE:-$ROOT_DIR/config/images.conf}"
SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
EXIT_CODE="${TRIVY_EXIT_CODE:-0}"
FORMAT="${TRIVY_FORMAT:-table}"

usage() {
  cat <<EOF
Usage: $0 [--gate-critical|--gate-high-critical]

Environment:
  IMAGE_FILE          default: config/images.conf
  TRIVY_SEVERITY      default: HIGH,CRITICAL
  TRIVY_EXIT_CODE     default: 0
  TRIVY_FORMAT        default: table
EOF
}

case "${1:-}" in
  --gate-critical)
    SEVERITY="CRITICAL"
    EXIT_CODE=1
    ;;
  --gate-high-critical)
    SEVERITY="HIGH,CRITICAL"
    EXIT_CODE=1
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

[[ -f "$IMAGE_FILE" ]] || {
  echo "ERROR: $IMAGE_FILE not found." >&2
  echo "Copy config/images.conf.example to config/images.conf and edit it." >&2
  exit 1
}

mkdir -p logs
ts="$(date '+%Y%m%d_%H%M%S')"
summary="logs/trivy-images-$ts.log"
overall=0

echo "Trivy image scan" | tee "$summary"
echo "severity=$SEVERITY exit_code=$EXIT_CODE" | tee -a "$summary"
echo | tee -a "$summary"

while IFS= read -r image || [[ -n "$image" ]]; do
  image="${image%%#*}"
  image="$(printf '%s' "$image" | xargs)"
  [[ -n "$image" ]] || continue

  safe="$(printf '%s' "$image" | tr '/:@' '____' | tr -cd '[:alnum:]_.-')"
  report="logs/trivy-$safe-$ts.txt"

  echo "=== $image ===" | tee -a "$summary"

  set +e
  trivy image     --scanners vuln     --severity "$SEVERITY"     --exit-code "$EXIT_CODE"     --format "$FORMAT"     "$image" 2>&1 | tee "$report"
  rc=${PIPESTATUS[0]}
  set -e

  echo "exit_code=$rc report=$report" | tee -a "$summary"
  echo | tee -a "$summary"

  if [[ "$rc" -ne 0 ]]; then
    overall=1
  fi
done < "$IMAGE_FILE"

echo "Summary: $summary"

if [[ "$overall" -ne 0 ]]; then
  echo "RESULT: vulnerability gate failed." >&2
  exit 1
fi

echo "RESULT: scan completed."
