# Registrul piloților

## Head of IT Weekly Planning

Stack detectat: Drupal 11/PHP 8.3, FastAPI/Python, Docker/Compose. CI-ul existent
folosește runnere self-hosted și rămâne nemodificat. Noul audit este manual și separat.

## Construction Company Management

Stack detectat: .NET 8, React/TypeScript/Vite, Flutter/Dart și Docker/Compose.
Repository-ul are deja numeroase release gates; pilotul adaugă numai auditul general
open-source și nu schimbă workflow-ul `Construction ERP CI`.

## ARCOM New Website Drupal 11

Stack detectat: Drupal 11/PHP 8.3, Composer și Docker. CI-ul existent include deja
Composer audit, Drupal coding standards, PHPStan și Trivy image scan. Noul audit
manual completează această acoperire cu Semgrep, Gitleaks, scanare repository/IaC,
MegaLinter și SBOM, fără să modifice gate-ul existent.

## shop.iplisse.md

Stack detectat: Next.js 16, React 19, TypeScript, Supabase și Docker. Branch-ul
implicit este `staging`. Auditul este adăugat pe acest branch printr-un branch/PR
dedicat și nu modifică deploymentul sau controalele staging existente.

## Website Magazine Components (magazin componente electronice)

Stack detectat: WooCommerce/WordPress, ERPNext, Python/FastAPI, OpenSearch, Redis și
mai multe stackuri Docker Compose. Auditul general scanează întreg repository-ul și
produce inventar SBOM; nu pornește și nu modifică mediile documentate.

## Exclus explicit

`Construction-Company-Management-New` este read-only și nu este modificat.

## Profil aplicat

Toate repository-urile de mai sus folosesc `manual-nonblocking-v1`, definit în
`REPOSITORY-ONBOARDING-STANDARD.md`.
