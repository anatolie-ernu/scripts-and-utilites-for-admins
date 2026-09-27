# Plan de testare și integrare Falco Runtime IDS

**Status:** PLANIFICAT — NEIMPLEMENTAT  
**Brand:** ERNU.EU  
**Scop:** validarea Falco ca strat de Runtime Intrusion Detection pentru
platforme Linux containerizate.

## 1. Decizia curentă

Falco nu se instalează încă pe producție.

Ordinea aprobată este:

```text
Documentare
   -> host de test
   -> compatibilitate Modern eBPF
   -> test funcțional
   -> măsurare overhead
   -> tuning reguli
   -> alertare
   -> review securitate
   -> decizie producție
```

Nu se introduce momentan:

- pachet Falco pe hosturile de producție;
- container Falco în stack-urile de producție;
- acțiune automată de kill/quarantine/ban;
- acces Docker socket fără justificare/test.

## 2. De ce Falco

Falco acoperă o zonă diferită de WAF și Fail2Ban.

```text
WAF        -> request HTTP malițios
Fail2Ban   -> pattern de log -> IP ban
Falco      -> comportament runtime / procese / syscall-uri
Backup     -> recovery
```

Exemplu de eveniment cu valoare ridicată:

```text
php-fpm -> /bin/sh
```

Într-un workload web normal aceasta trebuie investigată.

## 3. Model tehnic candidat

Prima opțiune de test:

```text
Falco container
  engine: modern_ebpf
  policy: detect/log/alert
  capabilities: minimum validated set
  mounts: read-only where possible
  rules: versioned in Git
```

Alternativa:

```text
Falco native package
  systemd
  modern eBPF
```

Alegerea finală se face după rezultate, nu înainte.

## 4. Checklist host de test

Colectează:

```bash
uname -a
uname -r
cat /etc/os-release
docker version
docker compose version

mount | grep -E 'tracefs|debugfs'
ls -ld /sys/kernel/tracing /sys/kernel/debug/tracing 2>/dev/null
sysctl -n net.core.bpf_jit_enable
```

Documentează:

- versiunea kernel;
- arhitectura CPU;
- versiunea Docker;
- disponibilitatea tracefs;
- starea BPF JIT;
- AppArmor/SELinux;
- restricții de capabilities.

## 5. Teste minime

### T01 — pornire Falco

Criteriu:

- proces/container stabil;
- Modern eBPF activ;
- fără kernel module dacă Modern eBPF funcționează;
- logs disponibile.

### T02 — shell în container de test

Generează intenționat un shell într-un container disposable.

Criteriu:

- Falco detectează evenimentul;
- alertă identificabilă;
- container/process metadata suficiente.

### T03 — proces neobișnuit

Rulează controlat un utilitar precum curl/wget într-un container de test.

Criteriu:

- regula custom poate detecta execuția;
- se poate diferenția de mentenanță legitimă.

### T04 — write sensibil

Scriere controlată într-o zonă de test definită ca sensibilă.

Criteriu:

- alertă fără blocare automată.

### T05 — activitate normală

Rulează:

- backup;
- logrotate;
- health check;
- deploy;
- CLI administrativ.

Criteriu:

- se inventariază toate false-positive-urile;
- nu se dezactivează reguli global fără analiză.

### T06 — resurse

Măsoară:

- CPU;
- RAM;
- I/O;
- număr evenimente/sec;
- impact asupra workload-ului.

### T07 — restart/reboot

Criteriu:

- Falco revine automat;
- workload-urile aplicației nu depind de Falco pentru pornire;
- indisponibilitatea Falco nu blochează serviciul web.

## 6. Reguli candidate

Prioritate inițială:

1. shell pornit de PHP/application runtime;
2. shell într-un container DB/cache;
3. execuție de network tools neașteptate;
4. modificări în fișiere/configurații sensibile;
5. mount/namespace/privilege anomalies.

Regulile trebuie versionate și testate individual.

## 7. Logging

Ținta propusă:

```text
logs/falco/
├── falco.log
└── events.json
```

În producție se va integra cu rotația de log și, ulterior, cu platforma de
monitorizare/SIEM dacă testele justifică integrarea.

## 8. Docker socket

`/var/run/docker.sock` este o suprafață privilegiată.

În test se verifică dacă este necesar pentru metadata dorită. Dacă Falco poate
furniza detecțiile necesare fără socket, se preferă varianta fără socket.

Dacă devine obligatoriu:

- se documentează motivul;
- se documentează riscul;
- se testează izolarea;
- se include în review-ul de producție.

## 9. Criterii de acceptare

Falco poate trece spre pilot doar dacă:

- funcționează stabil cu kernel-ul țintă;
- overhead-ul este acceptabil;
- detecțiile critice sunt reproductibile;
- false-positive-urile pot fi controlate;
- logurile sunt administrabile;
- upgrade/rollback sunt documentate;
- modelul de capabilities este acceptat;
- Docker socket este eliminat sau justificat;
- nu este necesară auto-remediere pentru valoarea inițială.

## 10. Rezultat așteptat

La finalul testării se emite una dintre decizii:

```text
APPROVE FOR PILOT
APPROVE WITH CONDITIONS
RETEST
REJECT FOR CURRENT PLATFORM
```

Până atunci starea rămâne:

**DOCUMENTED / NOT IMPLEMENTED / TEST FIRST**
