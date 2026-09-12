# Recomandarea inițială consolidată

Pentru testarea codului sursă, code compliance și review automat este recomandat un
stack, nu un singur produs:

- **SonarQube Community Build**: buguri, code smells, duplicare, complexitate,
  coverage și Quality Gate. Varianta Community oficială este orientată spre analiza
  ramurii principale; capabilitățile complete branch/PR trebuie verificate separat.
- **Semgrep CE**: SAST și reguli organizaționale proprii.
- **MegaLinter**: orchestrarea linters pentru C#, TypeScript/JavaScript, Python,
  PHP, Dart, YAML, Markdown, Docker și shell.
- **Trivy**: CVE, imagini, filesystem, secrete și configurații IaC.
- **Gitleaks**: detectarea specializată a secretelor și verificarea Git.
- **OSS Review Toolkit**: SBOM, licențe, copyright și policy-as-code.
- **Reviewdog**: comentarii automate pe liniile modificate.
- **PR-Agent + Ollama**: review AI self-hosted opțional, exclusiv consultativ.

Quality Gate-ul matur trebuie să combine build, teste, coverage, SAST, secrete,
dependențe, licențe și aprobare umană. La Pull Request rulează controalele rapide;
după merge sau înainte de deployment rulează analiza completă, scanarea imaginii,
SBOM, DAST pe o țintă autorizată și validarea de staging.

Implementarea pilot din acest director păstrează toate verificările manuale și
neblocante până la calibrarea pragurilor și aprobarea formală.

