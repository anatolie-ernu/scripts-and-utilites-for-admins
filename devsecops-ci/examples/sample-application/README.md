# Exemplu depersonalizat - sample-application

Acest exemplu folosește exclusiv date fictive: `example-org/sample-application`.
Nu descrie și nu enumeră implementări reale.

## Fișiere

- [Workflow generic](../../templates/github/manual-devsecops-generic.yml)
- [Parametri](devsecops/config/project.env.example)
- [Reguli Semgrep](devsecops/config/.semgrep.yml)
- [Profil MegaLinter](devsecops/config/.mega-linter.yml)
- [Reguli Gitleaks](devsecops/config/gitleaks.toml)
- [SonarQube](devsecops/sonar-project.properties)
- [Rulare locală](devsecops/scripts/run-local-audit.sh)
- [Validare](devsecops/scripts/validate-configs.sh)
- [Exemplu gate blocant](devsecops/workflows/recommended-blocking.yml.example)

Profil inițial: `manual-nonblocking-v1`. Țintă: `recommended-enterprise-v1`.
