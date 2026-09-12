# Standard reproductibil de integrare a unui repository

Acest document este sursa autoritativă pentru cererea ulterioară **„aplică aceeași
verificare DevSecOps pe repository-ul X”**.

Versiunea țintă recomandată pentru replicare este `recommended-enterprise-v1`,
descrisă în `RECOMMENDED-ENTERPRISE-STACK.md`. Profilul manual este etapa de
onboarding și calibrare înainte de activarea controalelor obligatorii.

## Profil standard: `manual-nonblocking-v1`

La aplicarea profilului se execută obligatoriu următorii pași:

1. Audit read-only: reguli `AGENTS.md`, README, roadmap, limbaje, lockfiles,
   containere, CI existent, branch implicit și permisiuni.
2. Nu se modifică workflow-urile existente de build/deploy.
3. Se adaugă `.github/workflows/manual-devsecops-audit.yml`.
4. Triggerul permis este numai `workflow_dispatch`.
5. Permisiunea implicită este `contents: read`.
6. Se rulează Semgrep CE, Trivy filesystem, Gitleaks și MegaLinter.
7. Se generează SBOM CycloneDX prin Trivy.
8. Se încarcă artefacte chiar dacă un scanner identifică probleme.
9. Nu se configurează Required Status Checks și nu se schimbă Branch Protection.
10. Se adaugă un document `docs/DEVSECOPS-MANUAL-AUDIT.md` cu scop, operare,
    interpretare, secrete opționale și rollback.
11. Se validează YAML și se confirmă lipsa triggerelor automate.
12. Modificarea se publică într-un branch separat și PR, dacă utilizatorul nu cere
    explicit commit direct pe branch-ul implicit.

## Contractul rezultatelor

| Artefact | Conținut |
|---|---|
| `semgrep-report` | constatări SAST în SARIF |
| `trivy-report` | CVE, secrete și misconfiguration în SARIF |
| `gitleaks-report` | secrete Git în SARIF |
| `megalinter-reports` | rapoarte linters multi-limbaj |
| `sbom-cyclonedx` | inventar de componente CycloneDX JSON |

## Adaptări permise

Se pot adăuga build/teste native în funcție de stack, dar nu se elimină controalele
de bază. Directoarele generate (`vendor`, `node_modules`, `build`, `dist`, artefacte)
se exclud justificat. Orice trecere la rulare automată sau blocking constituie profil
nou și necesită aprobare explicită.

După calibrare, profilul țintă include obligatoriu SonarQube Community, Semgrep CE,
MegaLinter, Trivy, Gitleaks și Reviewdog; ORT este activat pentru compliance/release,
iar PR-Agent + Ollama poate fi activat pentru review AI self-hosted consultativ.

## Convenții

- Nume workflow: `Manual DevSecOps Audit`.
- Nume fișier: `.github/workflows/manual-devsecops-audit.yml`.
- Timeout per job: maximum 30 minute în profilul standard.
- Retenție artefacte: 14 zile.
- Repository-ul `*-New` este exclus dacă utilizatorul nu îl autorizează explicit.
- Secretele și adresele interne nu se includ în fișiere sau artefacte.

## Evoluție controlată

Versiunea profilului se schimbă numai când se modifică triggerul, setul minim de
scanere, permisiunile sau contractul artefactelor. Repository-urile onboardate se
înregistrează în `docs/PILOTS.md` cu data, profilul și particularitățile stackului.
