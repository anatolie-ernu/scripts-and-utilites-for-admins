# Versiunea recomandată pentru replicare: `recommended-enterprise-v1`

## Decizie

> **SonarQube Community + Semgrep CE + MegaLinter + Trivy + Gitleaks +
> Reviewdog** reprezintă baza standard. Se adaugă **OSS Review Toolkit (ORT)**
> pentru conformitate, licențe și SBOM și **PR-Agent + Ollama** pentru review AI
> complet self-hosted. Stackul se distribuie printr-un workflow reutilizabil și
> devine obligatoriu pentru toate repository-urile după etapa de calibrare.

## Componente

| Componentă | Statut | Responsabilitate |
|---|---|---|
| SonarQube Community | obligatoriu | quality dashboard, maintainability, bugs, coverage |
| Semgrep CE | obligatoriu | SAST și reguli organizaționale proprii |
| MegaLinter | obligatoriu | code style și compliance multi-limbaj |
| Trivy | obligatoriu | CVE, imagini, repository, secrete și IaC |
| Gitleaks | obligatoriu | secrete în fișiere și istoricul Git |
| Reviewdog | obligatoriu în faza PR | comentarii inline din rezultatele deterministe |
| ORT | obligatoriu pentru release/compliance | licențe, copyright, policy-as-code, SBOM |
| PR-Agent + Ollama | recomandat | review AI self-hosted, exclusiv consultativ |

## Model de replicare

1. Repository-ul central menține workflow-ul reutilizabil, versiunile și politicile.
2. Fiecare repository consumator fixează workflow-ul la un tag aprobat, nu la `main`.
3. Profilul pornește ca `manual-nonblocking-v1` pentru 2-4 săptămâni.
4. După triere și baseline, se activează `pull_request` în mod informativ.
5. Controalele deterministe critice devin Required Status Checks.
6. ORT rulează la release și periodic; politica de licențe este aprobată juridic.
7. PR-Agent rulează self-hosted cu Ollama și nu decide merge-ul.

## Ordinea de activare a blocării

1. secrete confirmate;
2. build și teste;
3. vulnerabilități CRITICAL remediabile;
4. reguli Semgrep `ERROR` confirmate;
5. Quality Gate SonarQube pe cod nou, unde capabilitatea este disponibilă;
6. linters pe cod nou/modificat;
7. policy ORT pentru licențe `deny` și `unknown`;
8. praguri HIGH și coverage după aprobarea proiectului.

Reviewdog doar publică rezultatele. PR-Agent + Ollama rămâne consultativ și nu este
niciodată singurul control care blochează integrarea.

## Regula pentru repository-uri noi

Orice repository nou trebuie onboardat cel puțin cu `manual-nonblocking-v1`.
Ținta organizațională este `recommended-enterprise-v1`. Excluderea unui control
obligatoriu necesită justificare, proprietar, control compensator, aprobator și
dată de expirare.

