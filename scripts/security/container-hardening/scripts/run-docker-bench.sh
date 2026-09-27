#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || {
  echo "ERROR: run as root." >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git not found." >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BENCH_REF="${DOCKER_BENCH_REF:-v1.6.1}"
IMAGE_TAG="ernu/docker-bench-security:${BENCH_REF#v}"
mkdir -p logs

tmp="$(mktemp -d /tmp/docker-bench-security.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "[docker-bench] cloning official source ref=$BENCH_REF"
git clone --quiet --depth 1 --branch "$BENCH_REF"   https://github.com/docker/docker-bench-security.git "$tmp"

echo "[docker-bench] building local audit image $IMAGE_TAG"
docker build --quiet --no-cache -t "$IMAGE_TAG" "$tmp" >/dev/null

ts="$(date '+%Y%m%d_%H%M%S')"
report="$ROOT_DIR/logs/docker-bench-$ts.log"

args=(
  docker run --rm
  --net host
  --pid host
  --userns host
  --cap-add audit_control
  -v /etc:/etc:ro
  -v /var/lib:/var/lib:ro
  -v /var/run/docker.sock:/var/run/docker.sock:ro
  --label docker_bench_security
)

[[ -e /usr/bin/containerd ]] && args+=(-v /usr/bin/containerd:/usr/bin/containerd:ro)
[[ -e /usr/bin/runc ]] && args+=(-v /usr/bin/runc:/usr/bin/runc:ro)
[[ -d /lib/systemd/system ]] && args+=(-v /lib/systemd/system:/lib/systemd/system:ro)
[[ -d /usr/lib/systemd ]] && args+=(-v /usr/lib/systemd:/usr/lib/systemd:ro)

args+=("$IMAGE_TAG" -b -p)

echo "[docker-bench] report=$report"
set +e
"${args[@]}" 2>&1 | tee "$report"
rc=${PIPESTATUS[0]}
set -e

echo
echo "[docker-bench] exit_code=$rc"
exit "$rc"
