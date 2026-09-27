#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || {
  echo "ERROR: run as root so host PID/UID mappings can be inspected." >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }

name="ernu-userns-check-$$"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== Docker security options ==="
docker info --format '{{range .SecurityOptions}}{{println .}}{{end}}'
echo

echo "=== subordinate UID/GID mappings ==="
grep -E '^(dockremap|docker|root):' /etc/subuid 2>/dev/null || echo "(no matching /etc/subuid entry)"
grep -E '^(dockremap|docker|root):' /etc/subgid 2>/dev/null || echo "(no matching /etc/subgid entry)"
echo

docker run -d --name "$name" alpine:3.22 sleep 300 >/dev/null
pid="$(docker inspect -f '{{.State.Pid}}' "$name")"

echo "=== disposable container ==="
echo "container=$name"
echo "host_pid=$pid"
ps -o uid,gid,pid,ppid,cmd -p "$pid"
echo

echo "=== /proc/$pid/uid_map ==="
cat "/proc/$pid/uid_map"
echo

echo "=== /proc/$pid/gid_map ==="
cat "/proc/$pid/gid_map"
echo

host_uid="$(ps -o uid= -p "$pid" | xargs)"

if [[ "$host_uid" == "0" ]]; then
  echo "RESULT: container root is visible as host UID 0."
  echo "userns-remap does not appear active for this test container."
  exit 2
fi

echo "RESULT: container process maps to host UID $host_uid."
echo "Review uid_map/gid_map and Docker SecurityOptions to confirm the intended remap."
