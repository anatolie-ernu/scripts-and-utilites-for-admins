#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash -n "${repo_root}/devsecops/scripts/run-local-audit.sh"
test -s "${repo_root}/devsecops/sonar-project.properties"
test -s "${repo_root}/devsecops/config/project.env.example"
test -s "${repo_root}/devsecops/config/.semgrep.yml"
test -s "${repo_root}/devsecops/config/.mega-linter.yml"
test -s "${repo_root}/devsecops/config/gitleaks.toml"
echo "Exemplu depersonalizat valid."
