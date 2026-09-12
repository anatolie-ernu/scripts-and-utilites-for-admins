#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
report_dir="${repo_root}/devsecops/reports"
mkdir -p "${report_dir}"
command -v docker >/dev/null || { echo "Docker este necesar." >&2; exit 2; }
docker run --rm -v "${repo_root}:/src" -w /src semgrep/semgrep:latest semgrep scan --config /src/devsecops/config/.semgrep.yml --config p/default --sarif --output /src/devsecops/reports/semgrep.sarif . || semgrep_status=$?
docker run --rm -v "${repo_root}:/src" aquasec/trivy:latest fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --format sarif --output /src/devsecops/reports/trivy.sarif /src
docker run --rm -v "${repo_root}:/src" zricethezav/gitleaks:latest detect --source=/src --config=/src/devsecops/config/gitleaks.toml --report-format=sarif --report-path=/src/devsecops/reports/gitleaks.sarif --exit-code=0
docker run --rm -v "${repo_root}:/tmp/lint" -e MEGALINTER_CONFIG=devsecops/config/.mega-linter.yml oxsecurity/megalinter:v9
printf 'Rapoarte: %s; Semgrep status=%s\n' "${report_dir}" "${semgrep_status:-0}"
