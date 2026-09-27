# Integrarea template-ului Container Hardening într-un proiect

## 1. Copiere

Copiază directorul în repository-ul proiectului, de exemplu:

```text
ops/security/container-hardening/
```

Nu copia rapoartele din `logs/`.

## 2. Inventarul imaginilor

```bash
cp config/images.conf.example config/images.conf
```

Înlocuiește exemplele cu tag-urile aprobate de proiect.

Preferă tag-uri exacte:

```text
nginx:1.30.5-alpine
```

în loc de:

```text
nginx:latest
```

Pentru control maxim, proiectele pot folosi digest-uri OCI aprobate.

## 3. Instalare Trivy

```bash
sudo bash scripts/install-trivy.sh
```

Dacă proiectul folosește management centralizat de pachete, instalarea Trivy se
face prin acel mecanism și scriptul local rămâne doar fallback/documentație.

## 4. Validare inițială

```bash
bash scripts/bootstrap.sh
bash scripts/validate-template.sh
bash scripts/scan-images.sh
sudo bash scripts/run-docker-bench.sh
sudo bash scripts/verify-userns-remap.sh
```

## 5. Integrare în deployment

Înainte de deployment:

```bash
bash scripts/check-compose-hardening.sh /project/compose.yml
TRIVY_SEVERITY=CRITICAL TRIVY_EXIT_CODE=1 bash scripts/scan-images.sh
```

Nu lega direct `docker-image-maintenance.sh --pull` de `docker compose up`
într-un proiect critic fără:

- backup;
- staging;
- health gate;
- rollback;
- aprobare/release control.

## 6. Excepții

Exemple de excepții care trebuie documentate:

- container care necesită `NET_ADMIN`;
- root filesystem care nu poate fi read-only;
- healthcheck imposibil pentru un sidecar;
- Docker socket necesar unui control de securitate;
- userns-remap incompatibil cu anumite bind mounts.

Pentru fiecare excepție păstrează:

```text
control
motiv
risc
compensating control
owner
data revizuirii
```

## 7. userns-remap

Pe host existent, nu activa direct.

Fă întâi:

```bash
sudo bash scripts/verify-userns-remap.sh
```

Dacă politica proiectului cere activare:

1. backup și inventar Docker;
2. host/staging test;
3. verificare bind mounts și ownership;
4. plan de rollback;
5. modificare daemon.json;
6. restart Docker într-o fereastră aprobată;
7. redeploy și verificare.

## 8. Timere

Pentru host standalone:

```bash
sudo bash scripts/install-systemd-timers.sh
```

În medii orchestrate/CI, preferă schedulerul platformei și reutilizează
scripturile fără unitățile systemd.

## 9. Runtime IDS

Container hardening este complementar cu Falco.

Template separat:

```text
scripts/security/falco-runtime-ids/
```

Ordinea recomandată:

```text
image scan -> host/config hardening -> deploy -> runtime IDS
```
