#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0

echo "=== Falco Runtime IDS preflight ==="
echo "host=$(hostname)"
echo "kernel=$(uname -r)"
echo

for cmd in docker grep awk; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "OK: $cmd"
  else
    echo "ERROR: missing $cmd"
    fail=1
  fi
done

if docker compose version >/dev/null 2>&1; then
  echo "OK: docker compose"
else
  echo "ERROR: docker compose plugin not available"
  fail=1
fi

tracefs="${TRACEFS_HOST:-}"
if [[ -z "$tracefs" && -f .env ]]; then
  tracefs="$(sed -n 's/^TRACEFS_HOST=//p' .env | tail -1)"
fi
tracefs="${tracefs:-/sys/kernel/tracing}"

echo
echo "TRACEFS_HOST=$tracefs"
if [[ -d "$tracefs" ]]; then
  echo "OK: tracefs directory exists"
else
  echo "ERROR: tracefs directory does not exist"
  if [[ -d /sys/kernel/debug/tracing ]]; then
    echo "HINT: use TRACEFS_HOST=/sys/kernel/debug/tracing"
  fi
  fail=1
fi

echo
echo "=== BPF JIT ==="
if sysctl -n net.core.bpf_jit_enable >/dev/null 2>&1; then
  value="$(sysctl -n net.core.bpf_jit_enable)"
  echo "net.core.bpf_jit_enable=$value"
else
  echo "INFO: net.core.bpf_jit_enable is not exposed on this host."
fi

echo
echo "=== Docker ==="
docker version --format 'Server={{.Server.Version}} Client={{.Client.Version}}' || fail=1
docker compose version || fail=1

echo
echo "=== Security modules ==="
[[ -r /sys/module/apparmor/parameters/enabled ]] && {
  printf 'AppArmor='
  cat /sys/module/apparmor/parameters/enabled
}
command -v getenforce >/dev/null 2>&1 && echo "SELinux=$(getenforce)" || true

echo
if [[ "$fail" -ne 0 ]]; then
  echo "RESULT: PREFLIGHT FAILED"
  exit 1
fi

echo "RESULT: PREFLIGHT OK"
