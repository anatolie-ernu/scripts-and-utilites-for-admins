#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || {
  echo "ERROR: run as root." >&2
  exit 1
}

command -v apt-get >/dev/null 2>&1 || {
  echo "ERROR: this installer supports Debian/Ubuntu apt hosts." >&2
  exit 1
}

echo "[trivy] Installing from the official Aqua Security Debian repository."

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

install -d -m 0755 /usr/share/keyrings
tmp_key="$(mktemp)"
trap 'rm -f "$tmp_key"' EXIT

curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key -o "$tmp_key"
gpg --dearmor --yes -o /usr/share/keyrings/trivy.gpg "$tmp_key"
chmod 0644 /usr/share/keyrings/trivy.gpg

cat > /etc/apt/sources.list.d/trivy.list <<'EOF'
deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main
EOF

apt-get update

if [[ -n "${TRIVY_VERSION:-}" ]]; then
  echo "[trivy] Requested package version: $TRIVY_VERSION"
  apt-get install -y "trivy=$TRIVY_VERSION"
else
  apt-get install -y trivy
fi

echo
trivy --version
