# Falco Runtime IDS Template

Reusable ERNU.EU template for runtime intrusion detection on Linux Docker hosts.

**Status:** implementation template ready / test before production  
**Pinned Falco baseline:** 0.45.2  
**Engine:** Modern eBPF  
**Initial policy:** DETECT -> LOG -> ALERT  
**Brand:** ERNU.EU | IT & Security Solutions

This directory contains the complete reusable template: Dockerfile, Docker
Compose, configuration overlays, custom rules, test generators, validation,
reporting and implementation documentation.

It is **not automatically deployed to production**. Every target project must
first validate the template on a dedicated test/staging host.

## Architecture

```text
Internet
  -> CDN / edge
  -> WAF / reverse proxy
  -> application containers
       - nginx
       - PHP/application runtime
       - database
       - cache

Security layers
  - WAF / reverse proxy   -> HTTP/application attacks
  - Fail2Ban              -> log-driven IP blocking
  - application security  -> CMS/application controls
  - Falco                 -> kernel/runtime behavior detection
  - backup                -> recovery/resilience
```

Falco complements the existing controls; it does not replace them.

## Repository layout

```text
falco-runtime-ids/
├── README.md
├── Dockerfile
├── compose.yml
├── compose.docker-metadata.yml
├── .env.example
├── .gitignore
├── Makefile
├── .github-actions-example.yml
├── config/
│   └── 10-ernu-runtime.yaml
├── rules.d/
│   ├── ernu-container.yaml
│   ├── ernu-web-runtime.yaml
│   └── ernu-filesystem.yaml
├── scripts/
│   ├── preflight.sh
│   ├── validate.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── status.sh
│   ├── test-alerts.sh
│   ├── report.sh
│   └── update-version.sh
├── examples/
│   ├── compose.project-override.yml
│   └── falco.logrotate
├── docs/
│   ├── IMPLEMENTATION-GUIDE-RO.md
│   └── TEST-AND-IMPLEMENTATION-PLAN-RO.md
├── logs/
└── reports/
```

## Why Modern eBPF

Falco's current official Docker documentation states that Modern eBPF is
bundled into Falco and does not require separate driver installation.

The template therefore uses:

```yaml
engine:
  kind: modern_ebpf
```

The default Compose service follows Falco's least-privileged Docker model:

```text
cap_drop: ALL
cap_add:
  - SYS_ADMIN
  - SYS_RESOURCE
  - SYS_PTRACE
```

The host paths used for kernel/runtime visibility are:

```text
/sys/kernel/tracing -> /sys/kernel/tracing:ro
/proc               -> /host/proc:ro
/etc                -> /host/etc:ro
```

Some hosts expose tracefs at `/sys/kernel/debug/tracing`. Set
`TRACEFS_HOST` in `.env` accordingly.

Official reference:

- https://falco.org/docs/setup/container/

## Docker socket policy

The base `compose.yml` intentionally does **not** mount Docker socket.

If test results show that richer Docker container metadata is required, start
with the explicit override:

```bash
bash scripts/start.sh --docker-metadata
```

which adds:

```text
/var/run/docker.sock:/host/var/run/docker.sock
```

Treat Docker socket access as highly privileged and document the decision in
the target project.

## Custom detections

### Container shell

`ernu-container.yaml` detects shells and common network tools executed inside
containers.

### Web runtime -> shell

`ernu-web-runtime.yaml` adds high-value detections such as:

```text
php-fpm -> sh
php-fpm -> bash
PHP -> curl/wget/nc/socat
```

### Sensitive writes

`ernu-filesystem.yaml` detects container writes below selected system paths:

```text
/etc
/bin
/usr/bin
/usr/sbin
```

Rules must be tuned against legitimate deploy/update/maintenance activity
before production adoption.

## Quick start on a test host

```bash
cd falco-runtime-ids

cp .env.example .env

bash scripts/preflight.sh
bash scripts/validate.sh
bash scripts/start.sh
bash scripts/status.sh
bash scripts/test-alerts.sh
bash scripts/report.sh
```

To test with Docker metadata:

```bash
bash scripts/start.sh --docker-metadata
```

Stop:

```bash
bash scripts/stop.sh
```

Equivalent Make targets:

```bash
make preflight
make validate
make start
make status
make test
make report
make stop
```

## Generated data

Falco JSON alerts:

```text
logs/events.json
```

Generated summaries:

```text
reports/falco-summary-YYYYMMDD_HHMMSS.txt
```

Runtime logs/reports are ignored by Git.

## Version management

The template is pinned to Falco 0.45.2.

When upgrading:

```bash
bash scripts/update-version.sh 0.45.3
```

Then:

1. review upstream Falco release notes;
2. run `scripts/validate.sh`;
3. test on the dedicated host;
4. replay `scripts/test-alerts.sh`;
5. measure CPU/RAM/event volume;
6. review false positives;
7. commit the version change only after validation.

Current official release source:

- https://github.com/falcosecurity/falco/releases

## Production policy

Initial production mode, after approval:

```text
Falco
  -> DETECT
  -> LOG
  -> ALERT
```

Not enabled by this template:

```text
automatic process kill
automatic container stop
automatic IP ban
automatic quarantine
```

Automated response requires a separate risk assessment and test plan.

## Project integration

See:

```text
docs/IMPLEMENTATION-GUIDE-RO.md
docs/TEST-AND-IMPLEMENTATION-PLAN-RO.md
```

Official references:

- https://falco.org/docs/setup/container/
- https://falco.org/docs/concepts/rules/
- https://falco.org/docs/concepts/outputs/channels/
- https://falco.org/docs/configuration/
- https://github.com/falcosecurity/falco/releases

Copyright © 2026 ERNU.EU. All rights reserved.
