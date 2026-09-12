# Platformă DevSecOps CI open-source

Implementare de referință pentru auditarea manuală a codului sursă, securității,
dependențelor, secretelor, containerelor și conformității licențelor. Pilotul este
intenționat **neblocant**: workflow-urile pornesc numai prin `workflow_dispatch`.

## Componente

| Control | Instrument | Rezultat |
|---|---|---|
| Code quality | SonarQube Community Build | dashboard și Quality Gate pe ramura analizată |
| SAST / reguli proprii | Semgrep CE | SARIF și raport text |
| Stil / compliance | MegaLinter | rapoarte agregate pe limbaje |
| CVE, secrete, IaC | Trivy | SARIF, JSON și tabel |
| Secrete Git | Gitleaks | SARIF |
| Licențe și SBOM | Trivy; ORT opțional | CycloneDX/SPDX și policy-as-code |
| Review în PR | Reviewdog, faza 2 | comentarii pe diff |
| Review AI | PR-Agent + Ollama, faza 2 | recomandări consultative |

## Structură

```text
devsecops-ci/
├── config/                     # politici versionate
├── docs/                       # documentație completă
├── platform/sonarqube/         # stack central self-hosted
├── scripts/                    # rulare locală și validare
└── templates/github/           # workflow-uri reutilizabile/pilot
```

## Pornire rapidă

1. Citiți [ghidul complet](docs/IMPLEMENTATION-GUIDE-RO.md).
2. Copiați `platform/sonarqube/.env.example` ca `.env` și schimbați parolele.
3. Porniți SonarQube cu `docker compose up -d` din acel director.
4. Copiați workflow-ul potrivit în repository-ul aplicației.
5. Din GitHub: **Actions → Manual DevSecOps Audit → Run workflow**.

## Exemplu de utilizare

Template-ul se copiază într-un repository fictiv, de exemplu
`example-org/sample-application`. Limbajele și directoarele se adaptează după auditul
proiectului, fără publicarea numelor, structurii sau informațiilor din alte repository-uri.

Pentru integrarea identică a altui repository folosiți profilul autoritativ
[`manual-nonblocking-v1`](docs/REPOSITORY-ONBOARDING-STANDARD.md).

## Versiunea recomandată pentru replicare

Ținta enterprise este [`recommended-enterprise-v1`](docs/RECOMMENDED-ENTERPRISE-STACK.md):
SonarQube Community + Semgrep CE + MegaLinter + Trivy + Gitleaks + Reviewdog ca
bază obligatorie, ORT pentru conformitate și PR-Agent + Ollama pentru review AI
self-hosted consultativ.

## Principiu de promovare

În pilot, constatările sunt colectate ca artefacte și nu sunt Required Status Checks.
După calibrarea fals-pozitivelor, activarea automată și blocarea merge-ului se aprobă
separat, control cu control.
