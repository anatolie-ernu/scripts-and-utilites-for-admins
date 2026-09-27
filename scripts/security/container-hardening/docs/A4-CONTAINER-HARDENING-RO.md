# A.4 Container Hardening – Best Practices

**Document:** ERNU.EU Container Hardening Template  
**Platform:** Linux / Debian / Docker Engine / Docker Compose  
**Status:** reusable implementation template  
**Language:** Romanian

## A.4.0 Scop și model operațional

Container hardening nu înseamnă un singur control. Modelul recomandat combină:

```text
Image supply chain
  -> scan vulnerabilități
  -> versiuni/pinning
  -> update controlat

Docker host
  -> CIS-style audit
  -> daemon configuration
  -> user namespace / least privilege

Compose/runtime
  -> non-root where possible
  -> cap_drop
  -> no-new-privileges
  -> read_only
  -> tmpfs
  -> resource limits
  -> health checks
  -> minimal mounts/networks

Runtime security
  -> Falco / runtime IDS
  -> logs / SIEM
```

Acest director implementează partea A.4 ca template reutilizabil.

---

## A.4.1 Image Scanning with Trivy

### Obiectiv

Toate imaginile care urmează să intre într-un deployment trebuie scanate
înainte de promovare.

Exemple:

```bash
trivy image mariadb:11
trivy image wordpress:php8.3-fpm
trivy image nginx:alpine
trivy image redis:alpine
```

Scanare focalizată:

```bash
trivy image --severity HIGH,CRITICAL nginx:alpine
```

Gate pentru vulnerabilități CRITICAL:

```bash
trivy image --exit-code 1 --severity CRITICAL nginx:alpine
```

### Instalare

Template-ul oferă:

```bash
sudo ./scripts/install-trivy.sh
```

Versiunea este pin-uită prin `TRIVY_VERSION`. Nu se recomandă utilizarea
necontrolată a cuvântului `latest` în automatizare.

### Inventar de imagini

Copiază:

```bash
cp config/images.conf.example config/images.conf
```

și adaptează lista:

```text
nginx:alpine
wordpress:php8.3-fpm
mariadb:11
redis:alpine
```

### Scanarea întregului inventar

```bash
./scripts/scan-images.sh
```

Gate doar CRITICAL:

```bash
TRIVY_SEVERITY=CRITICAL TRIVY_EXIT_CODE=1 ./scripts/scan-images.sh
```

Rapoartele sunt scrise în `logs/`.

### Politică recomandată

- CRITICAL: blochează promovarea până la analiză/exceptare documentată;
- HIGH: review obligatoriu;
- MEDIUM/LOW: raportare și backlog;
- excepțiile trebuie să aibă justificare și termen de revizuire;
- nu ascunde global vulnerabilitățile `unfixed` doar pentru a obține un build verde.

---

## A.4.2 Docker Bench Security – Automated Audit

### Obiectiv

Docker Bench verifică o serie de best practices bazate pe CIS Docker
Benchmark.

Template-ul oferă:

```bash
sudo ./scripts/run-docker-bench.sh
```

### De ce nu folosim direct imaginea istorică

Repository-ul oficial Docker Bench avertizează că imaginea
`docker/docker-bench-security` este depășită.

Din acest motiv scriptul:

1. clonează repository-ul oficial;
2. checkout pe un ref pin-uit, implicit `v1.6.1`;
3. construiește local imaginea de audit;
4. execută auditul cu mount-urile/namespace-urile necesare;
5. salvează raportul în `logs/`;
6. elimină workspace-ul temporar.

### Privilegii

Docker Bench necesită vizibilitate extinsă asupra hostului:

- host network;
- host PID;
- host user namespace;
- Docker socket;
- /etc;
- /var/lib;
- runtime binaries.

Rulează-l numai ca job de audit controlat.

### Frecvență

Recomandare generică:

```text
weekly + după schimbări majore Docker daemon/runtime
```

---

## A.4.3 User Namespace Remapping – Verification

### Obiectiv

User namespace remapping permite ca UID 0 din container să fie mapat la un UID
neprivilegiat, cu număr mare, pe host.

Verificare:

```bash
sudo ./scripts/verify-userns-remap.sh
```

Scriptul:

1. verifică SecurityOptions din Docker;
2. inspectează `/etc/subuid` și `/etc/subgid`;
3. pornește un container disposable;
4. obține PID-ul procesului containerului pe host;
5. afișează UID/GID host;
6. afișează `/proc/<pid>/uid_map` și `gid_map`;
7. șterge containerul.

### Interpretare

Dacă root din container este remapat, UID-ul de pe host trebuie să fie în
intervalul subordinate UID, de regulă > 100000.

### Atenție la hosturile existente

Nu activa automat `userns-remap` pe un host de producție existent.

Docker documentează că activarea remapping-ului poate masca resurse Docker
existente din `/var/lib/docker` și poate necesita ajustarea permisiunilor
pentru bind mounts.

Template-ul include doar un exemplu:

```text
examples/daemon.userns-remap.example.json
```

El se aplică numai după test și plan de migrare.

---

## A.4.4 Controlled Docker Image Updates

### De ce nu facem auto-redeploy orb

Un script de tip:

```text
docker pull
docker compose up -d
docker image prune
```

rulat automat în producție poate introduce:

- regresii de aplicație;
- schimbări de major/minor version;
- incompatibilitate DB;
- imagine vulnerabilă nou introdusă;
- downtime fără rollback pregătit.

De aceea template-ul separă:

```text
PULL -> SCAN -> REPORT -> REVIEW -> DEPLOY
```

### Script

```bash
./scripts/docker-image-maintenance.sh --report
./scripts/docker-image-maintenance.sh --pull
```

`--report` scanează imaginile definite în `config/images.conf`.

`--pull` descarcă imaginile candidate, rulează Trivy și produce raport.
Nu recreează containerele.

Dacă scanarea CRITICAL eșuează, raportul este marcat failed și imaginea nu
trebuie promovată.

### Cleanup

Scriptul poate elimina doar imaginile dangling:

```bash
./scripts/docker-image-maintenance.sh --pull --prune-dangling
```

Nu folosește implicit `docker image prune -a`.

### Programare

Timer-ul systemd rulează săptămânal:

```text
ernu-docker-image-maintenance.timer
```

și execută modul `--pull --prune-dangling` ca staging local, nu deploy.

---

## A.4.5 Docker Compose Runtime Hardening Baseline

Template:

```text
examples/compose.hardening.example.yml
```

Controale candidate:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true
tmpfs:
  - /tmp
pids_limit: 200
init: true
```

Adaugă numai capabilitățile necesare:

```yaml
cap_add:
  - NET_BIND_SERVICE
```

Pe cât posibil:

- rulează ca user non-root;
- nu utiliza `privileged: true`;
- nu monta Docker socket în containere aplicație;
- folosește volume read-only pentru configurații;
- separă rețele frontend/backend;
- nu publica DB/cache pe host;
- folosește health checks;
- stabilește limite CPU/RAM/PIDs;
- minimizează imaginile și pachetele instalate.

### Verificare statică

```bash
./scripts/check-compose-hardening.sh /path/to/compose.yml
```

Acest script nu garantează conformitate CIS completă. Este un pre-check rapid
pentru greșeli comune înainte de review.

---

## A.4.6 Scheduled Security Maintenance

Instalare timere:

```bash
sudo ./scripts/install-systemd-timers.sh
```

Timere:

```text
ernu-docker-image-maintenance.timer
ernu-docker-bench.timer
```

Verificare:

```bash
systemctl list-timers 'ernu-docker-*'
journalctl -u ernu-docker-image-maintenance.service
journalctl -u ernu-docker-bench.service
```

Rapoartele rămân în:

```text
logs/
```

---

## A.4.7 Workflow recomandat înainte de deployment

```text
1. docker compose config
2. check-compose-hardening.sh
3. scan-images.sh
4. review Trivy HIGH/CRITICAL
5. Docker Bench host audit
6. backup aplicație/date
7. deployment controlat
8. health checks
9. runtime monitoring/Falco
10. rollback dacă health gate eșuează
```

---

## A.4.8 Checklist

| Control | Cerință |
|---|---|
| Image tags controlate | obligatoriu |
| Trivy înainte de deploy | obligatoriu |
| CRITICAL gate | recomandat/obligatoriu după politica proiectului |
| Docker Bench periodic | recomandat |
| userns-remap verificat | obligatoriu dacă politica îl cere |
| privileged containers | excepție justificată |
| cap_drop ALL | preferat |
| no-new-privileges | preferat |
| read_only rootfs | unde aplicația permite |
| Docker socket | interzis aplicațiilor; excepție documentată |
| DB/cache publicate | nu |
| resource limits | recomandat |
| healthcheck | obligatoriu pentru servicii critice |
| update automat cu redeploy | nu, decât cu workflow controlat |
| runtime IDS | Falco după testare |

---

## A.4.9 Referințe oficiale

- Trivy installation: https://www.trivy.dev/docs/latest/getting-started/installation/
- Docker userns-remap: https://docs.docker.com/engine/security/userns-remap/
- Docker Bench Security: https://github.com/docker/docker-bench-security

**ERNU.EU — Container Hardening Template**
