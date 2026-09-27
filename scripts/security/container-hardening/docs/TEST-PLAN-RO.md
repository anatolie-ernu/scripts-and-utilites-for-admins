# Container Hardening — Test Plan

**Status:** test before production.

## T01 Trivy installation

```bash
sudo ./scripts/install-trivy.sh
trivy --version
```

Pass:

- binary available;
- pinned version reported;
- vulnerability DB can be downloaded.

## T02 Image inventory scan

```bash
cp config/images.conf.example config/images.conf
./scripts/scan-images.sh
```

Pass:

- every configured image is processed;
- report file exists;
- exit code matches configured vulnerability gate.

## T03 Docker Bench

```bash
sudo ./scripts/run-docker-bench.sh
```

Pass:

- upstream source is checked out at expected ref;
- local image builds;
- audit completes;
- report file exists.

## T04 userns-remap verification

```bash
sudo ./scripts/verify-userns-remap.sh
```

Record:

- Docker SecurityOptions;
- /etc/subuid range;
- /etc/subgid range;
- host PID;
- host UID/GID;
- uid_map/gid_map.

Do not enable remapping as part of this test.

## T05 Compose hardening checker

```bash
./scripts/check-compose-hardening.sh examples/compose.hardening.example.yml
```

Pass:

- template passes required checks;
- deliberately insecure compose file produces warnings/errors.

## T06 Maintenance pull/scan

```bash
./scripts/docker-image-maintenance.sh --pull
```

Pass:

- images are pulled;
- Trivy runs after pull;
- no application containers are restarted;
- report is persisted.

## T07 systemd timers

```bash
sudo ./scripts/install-systemd-timers.sh
systemctl list-timers 'ernu-docker-*'
```

Pass:

- timers enabled;
- manual `systemctl start` of each service succeeds;
- logs are available.

## Acceptance

Before production adoption:

- HIGH/CRITICAL policy agreed;
- userns-remap decision documented;
- Docker Bench findings triaged;
- Compose exceptions documented;
- maintenance does not auto-redeploy;
- rollback/backup process exists;
- Falco/runtime IDS tested separately.
