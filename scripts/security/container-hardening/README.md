# Container Hardening Template

Reusable ERNU.EU template for Docker hosts and Docker Compose projects.

**Status:** template / test before production  
**Brand:** ERNU.EU | IT & Security Solutions

The template implements the operational controls described in chapter **A.4
Container Hardening – Best Practices**:

- A.4.1 Trivy image vulnerability scanning;
- A.4.2 Docker Bench Security audit;
- A.4.3 Docker user namespace remapping verification;
- A.4.4 controlled Docker image update/maintenance;
- A.4.5 Docker Compose runtime hardening baseline;
- A.4.6 scheduled weekly audits and reporting.

## Repository layout

```text
container-hardening/
├── README.md
├── .gitignore
├── config/
│   └── images.conf.example
├── docs/
│   ├── A4-CONTAINER-HARDENING-RO.md
│   └── TEST-PLAN-RO.md
├── examples/
│   ├── compose.hardening.example.yml
│   └── daemon.userns-remap.example.json
├── logs/
│   └── .gitkeep
├── scripts/
│   ├── check-compose-hardening.sh
│   ├── docker-image-maintenance.sh
│   ├── install-systemd-timers.sh
│   ├── install-trivy.sh
│   ├── run-docker-bench.sh
│   ├── scan-images.sh
│   └── verify-userns-remap.sh
└── systemd/
    ├── ernu-docker-bench.service
    ├── ernu-docker-bench.timer
    ├── ernu-docker-image-maintenance.service
    └── ernu-docker-image-maintenance.timer
```

## Quick start

Copy the template into the target project's repository, then:

```bash
cd container-hardening
cp config/images.conf.example config/images.conf

sudo ./scripts/install-trivy.sh
./scripts/scan-images.sh
sudo ./scripts/run-docker-bench.sh
sudo ./scripts/verify-userns-remap.sh
./scripts/check-compose-hardening.sh /path/to/project/compose.yml
```

For weekly scheduled audit jobs:

```bash
sudo ./scripts/install-systemd-timers.sh
```

## Important policy

The image-maintenance timer **does not automatically redeploy production
containers**. It can pull candidate images, scan them and write a report.
Production deployment remains a separate controlled action after review,
backup and health validation.

This is deliberate: automatically replacing production images solely because a
new tag appeared is not a safe generic deployment strategy.

## Trivy

The default install helper pins a configurable Trivy release instead of using an
unbounded `latest` in automation.

The official Trivy installation documentation currently supports:

- native binary / package installation;
- official container images;
- Docker socket mounting for scanning images present on the local Docker host.

## Docker Bench Security

The official Docker Bench repository notes that the historical prebuilt
`docker/docker-bench-security` image is out of date. This template therefore
clones a pinned upstream ref and builds the audit image locally before running
it.

Docker Bench needs extensive read-only host visibility and host namespaces to
evaluate the Docker host. Treat it as a privileged audit job, not as a
long-running application container.

## userns-remap

The verification helper is read-only. It does **not** enable user namespace
remapping.

Docker documents that enabling `userns-remap` on an existing Docker host can
change visibility/ownership expectations for existing Docker objects and bind
mounts. Plan and test enablement separately, preferably on a new host.

## Public repository policy

Do not commit:

- production IPs/hostnames;
- credentials;
- registry tokens;
- private registry URLs if sensitive;
- vulnerability reports containing confidential image names;
- local `config/images.conf` if it contains private image references.

Copyright © 2026 ERNU.EU. All rights reserved.
