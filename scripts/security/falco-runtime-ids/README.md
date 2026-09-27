# Falco Runtime IDS — design and test plan

> Status: **DOCUMENTED / NOT IMPLEMENTED / TEST FIRST**
>
> This directory contains the proposed design for integrating Falco runtime
> intrusion detection into containerized Linux web platforms. It is deliberately
> documentation-only. Do not deploy this design to production before validation
> on a dedicated test host.

Brand: **ERNU.EU | IT & Security Solutions**

## Purpose

Falco adds a runtime-detection layer below the web application and reverse
proxy. It observes Linux kernel events and can alert on behavior such as:

- interactive shells inside application containers;
- unexpected process execution;
- writes to sensitive paths;
- suspicious privilege or mount activity;
- unexpected network tooling or connections;
- PHP / application processes spawning shells or administration tools.

Falco complements, rather than replaces, controls such as:

- CDN / edge protection;
- WAF;
- reverse proxy controls;
- Fail2Ban;
- CMS/application security plugins;
- backup and recovery.

## Proposed architecture

```text
Internet
  -> CDN / edge
  -> WAF / reverse proxy
  -> web application containers
       - nginx
       - PHP / application runtime
       - database
       - cache
       - backup / maintenance

Security controls
  - WAF                  -> HTTP/application attacks
  - Fail2Ban             -> log-driven IP blocking
  - application security -> CMS/application controls
  - Falco                -> kernel/runtime behavior detection
  - backup               -> recovery/resilience
```

## Preferred deployment model for testing

The preferred test design is:

- Falco as a dedicated container;
- Modern eBPF engine;
- least-privilege capabilities where supported;
- explicit read-only host mounts required by Falco;
- JSON/event logging;
- custom rules stored in Git;
- detection and alerting only during the first test phase;
- no automatic kill, quarantine or IP ban actions.

Falco's official container documentation states that the Modern eBPF driver is
bundled with Falco and does not require separate driver installation. The
official least-privileged container example uses the capabilities and host
mounts required for kernel-event visibility.

Official references:

- https://falco.org/docs/setup/container/
- https://falco.org/docs/concepts/event-sources/kernel/
- https://falco.org/docs/setup/packages/

## Native host installation

A native DEB/systemd installation is also officially supported and remains a
valid fallback for hosts where containerized Modern eBPF is unsuitable.

Reference concept:

```bash
# Example only — do not run in production before test validation.
# Follow the current official Falco package documentation when testing.

apt update
apt install falco

# Service name depends on the selected driver/setup.
systemctl status falco-modern-bpf.service
```

The original operational idea was to install Falco directly on the Linux host.
For ERNU.EU containerized platforms, the preferred candidate is container +
Modern eBPF, subject to test results.

## Candidate custom detections

The initial custom ruleset should focus on high-value events with low expected
noise.

### Application runtime spawning a shell

Examples:

```text
php-fpm -> sh
php-fpm -> bash
php      -> dash
```

This can indicate command execution through an exploited application or plugin.

### Unexpected administration tools in application containers

Candidate commands:

```text
bash
sh
curl
wget
nc
ncat
socat
python
perl
```

These must be tuned against legitimate maintenance activity before production.

### Sensitive writes

Candidate paths:

```text
/etc/
/bin/
/usr/bin/
wp-config.php
wp-content/plugins/
wp-content/themes/
```

Rules must distinguish legitimate update/deploy operations from unexpected
runtime modification.

### Privilege / namespace / mount anomalies

Test detections for:

- unexpected privilege escalation;
- unusual mount operations;
- namespace manipulation;
- container escape indicators;
- unexpected process execution in database/cache containers.

## Docker socket caution

Do not mount `/var/run/docker.sock` automatically simply because it appears in
reference examples.

The Docker socket is highly privileged. During testing, determine whether
container metadata requirements justify exposing it to the Falco container.
If it is used:

- mount only where technically necessary;
- keep Falco isolated from application networks where possible;
- do not provide the socket to unrelated containers;
- document the threat model and rollback path.

## Test prerequisites

Before the first lab deployment collect:

```bash
uname -r
mount | grep -E 'tracefs|debugfs'
ls -ld /sys/kernel/tracing /sys/kernel/debug/tracing 2>/dev/null
sysctl -n net.core.bpf_jit_enable
docker version
docker compose version
```

For Modern eBPF, verify kernel compatibility, tracefs availability and BPF JIT
settings according to current Falco documentation.

## Test phases

### Phase 0 — documentation only

Current state.

- no package installation;
- no Falco container;
- no kernel changes;
- no production configuration.

### Phase 1 — isolated test host

Goals:

- start Falco with Modern eBPF;
- confirm syscall event collection;
- validate CPU/RAM overhead;
- validate container identification;
- confirm log persistence;
- verify restart behavior;
- verify no impact on Docker workloads.

### Phase 2 — controlled event generation

Generate known benign test events:

- shell inside a disposable test container;
- write to a test-sensitive path;
- execution of curl/wget in a disposable container;
- expected maintenance commands;
- backup activity;
- deployment activity.

Record expected vs observed alerts.

### Phase 3 — false-positive tuning

Build allowlists/exceptions for legitimate activity such as:

- backup jobs;
- WP-CLI or CMS CLI operations;
- deployment workflows;
- package/update operations;
- log rotation;
- health checks.

Do not broadly suppress rule classes merely to reduce noise.

### Phase 4 — alert pipeline

Only after the rules are stable evaluate:

- structured JSON log files;
- syslog;
- SIEM/OpenSearch/Elastic;
- Loki/Grafana;
- email/webhook notifications.

### Phase 5 — production readiness review

Production adoption requires documented results for:

- compatibility;
- resource consumption;
- alert volume;
- false-positive rate;
- fail/restart behavior;
- upgrade procedure;
- rollback;
- security impact of capabilities and mounts.

## Production policy

Initial production mode, if approved after testing:

```text
Falco
  -> DETECT
  -> LOG
  -> ALERT
```

Not initially:

```text
Falco -> kill process
Falco -> stop container
Falco -> ban IP
Falco -> automatic quarantine
```

Automated response may be considered only after a separate risk assessment.

## Proposed repository layout after successful testing

No executable files are committed yet. If testing is approved, the expected
layout is:

```text
scripts/security/falco-runtime-ids/
├── README.md
├── docs/
│   └── TEST-AND-IMPLEMENTATION-PLAN-RO.md
├── config/
│   ├── falco.yaml
│   └── rules.d/
│       ├── ernu-container.yaml
│       ├── ernu-web-runtime.yaml
│       └── ernu-filesystem.yaml
└── examples/
    └── compose.falco.example.yml
```

Executable/configuration artifacts should only be added after the test phase
confirms the required capabilities, mounts and rule behavior.

## Decision record

Current decision:

**Document now. Test later on a dedicated test system. Do not deploy Falco to
production yet.**

Copyright © 2026 ERNU.EU. All rights reserved.
