# Defense Scan: Trivy Priority Enrichment

**Status:** tested offline on sanitized sample data; validate against a live cluster before production  
**Brand:** ERNU.EU | IT & Security Solutions

Standard-library Python utility that reads `VulnerabilityReport` objects produced by the Trivy operator, adds the EPSS score and CISA KEV membership for every CVE, assigns a priority from P1 to P4, and writes a CSV sorted from most to least urgent.

## Repository layout

```text
defense-scan/
├── README.md
├── enrich_vulns.py
└── examples/
    ├── reports.json
    └── cache/
        ├── kev.json
        └── epss.json
```

`examples/cache/` contains synthetic test data for offline mode. Do not use it in production.

## Priorities

| Priority | Condition |
|---|---|
| P1 | CVE is in the CISA KEV catalog (known exploited), with or without a fix |
| P2 | EPSS is at or above the threshold (default 0.10) and a fixed version exists |
| P3 | Severity is CRITICAL or HIGH and a fixed version exists |
| P4 | Everything else |

The threshold is set with `--epss-threshold`. The default is a starting point and should be tuned after the first results.

## Usage

Export the reports from the cluster:

```bash
kubectl get vulnerabilityreports.aquasecurity.github.io -A -o json > reports.json
```

Run with network access. KEV and EPSS data are downloaded and cached in `cache/`:

```bash
python3 enrich_vulns.py reports.json -o priorities.csv
```

Run offline with a cache synchronized from a host that has internet access:

```bash
python3 enrich_vulns.py reports.json --cache-dir /srv/defense/cache --offline -o priorities.csv
```

Test with the bundled examples:

```bash
python3 enrich_vulns.py examples/reports.json --cache-dir examples/cache --offline -o /tmp/priorities.csv
```

## Options

| Option | Default | Purpose |
|---|---|---|
| `-o`, `--output` | `priorities.csv` | Output CSV path |
| `--cache-dir` | `cache` | Location of cached KEV and EPSS data |
| `--cache-hours` | `24` | Cache lifetime in hours |
| `--epss-threshold` | `0.10` | EPSS threshold for P2 |
| `--offline` | off | Use cached data only, without network access |

## Verify before production

- **Trivy operator labels.** The script reads `trivy-operator.resource.kind`, `trivy-operator.resource.name` and `trivy-operator.container.name` from report metadata. Confirm these against a real report with `kubectl get vulnerabilityreports -o yaml`, because label names can change between versions.
- **Feed URLs.** Confirm the KEV and EPSS endpoints on the first run with internet access.
- **EPSS response format.** The script expects the documented FIRST response shape with `data`, `cve` and `epss` fields.
- **Scope of prioritization.** The script does not know whether a service is publicly exposed. Add exposure context separately before acting on P2.

## Limitations

- Covers images of running workloads only. Application dependencies that never reach an image are not in the Trivy report.
- EPSS and KEV describe exploitation likelihood, not exposure. A P2 finding on an internal service may be less urgent than on an internet-facing one.
- The EPSS cache is refreshed when new CVEs appear, so cache age does not mean every score is the same age.

## Copyright

Copyright © 2026 ERNU.EU. All rights reserved.
