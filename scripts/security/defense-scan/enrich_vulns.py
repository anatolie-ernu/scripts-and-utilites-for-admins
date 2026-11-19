#!/usr/bin/env python3
"""Enrich Trivy operator VulnerabilityReports with EPSS and CISA KEV, and rank them.

Standard library only. Reads one or more JSON files exported from the cluster,
looks up EPSS scores and KEV membership for every CVE, assigns a priority and
writes a CSV sorted from most to least urgent.

Export the reports with:
    kubectl get vulnerabilityreports.aquasecurity.github.io -A -o json > reports.json

Priorities:
    P1  CVE is in the CISA KEV catalog (known exploited), fix or not
    P2  EPSS >= threshold and a fixed version exists
    P3  CRITICAL or HIGH severity and a fixed version exists
    P4  everything else
"""

import argparse
import csv
import json
import os
import sys
import time
import urllib.parse
import urllib.request

KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
EPSS_URL = "https://api.first.org/data/v1/epss"
EPSS_BATCH = 100

SEVERITY_RANK = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "UNKNOWN": 0}
CSV_FIELDS = [
    "priority", "cve", "severity", "in_kev", "epss", "namespace", "kind",
    "workload", "container", "image", "installed_version", "fixed_version",
    "fix_available", "title", "link",
]


def fetch_json(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "defense-scan/0.1"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def cache_is_fresh(path, max_age_hours):
    return os.path.exists(path) and (time.time() - os.path.getmtime(path)) < max_age_hours * 3600


def load_kev(cache_dir, max_age_hours, offline):
    path = os.path.join(cache_dir, "kev.json")
    if not cache_is_fresh(path, max_age_hours):
        if offline:
            sys.exit(f"offline mode: no fresh KEV cache at {path}")
        data = fetch_json(KEV_URL)
        os.makedirs(cache_dir, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return {v["cveID"] for v in data.get("vulnerabilities", []) if v.get("cveID")}


def load_epss(cves, cache_dir, max_age_hours, offline):
    """Return {cve: score or None}. None means EPSS has no score for that CVE."""
    path = os.path.join(cache_dir, "epss.json")
    scores = {}
    if cache_is_fresh(path, max_age_hours):
        with open(path, encoding="utf-8") as f:
            scores = json.load(f)

    missing = sorted(c for c in cves if c not in scores)
    if not missing:
        return scores

    if offline:
        print(f"warning: {len(missing)} CVE(s) without EPSS data in offline mode", file=sys.stderr)
        for c in missing:
            scores[c] = None
        return scores

    for i in range(0, len(missing), EPSS_BATCH):
        batch = missing[i:i + EPSS_BATCH]
        url = EPSS_URL + "?" + urllib.parse.urlencode({"cve": ",".join(batch)})
        found = {row["cve"]: float(row["epss"]) for row in fetch_json(url).get("data", [])}
        for c in batch:
            scores[c] = found.get(c)

    os.makedirs(cache_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(scores, f)
    return scores


def iter_findings(doc):
    """Yield one dict per vulnerability in a VulnerabilityReport list or single object."""
    if isinstance(doc, dict) and "items" in doc:
        reports = doc["items"]
    elif isinstance(doc, list):
        reports = doc
    else:
        reports = [doc]

    for rep in reports:
        meta = rep.get("metadata", {})
        labels = meta.get("labels", {})
        report = rep.get("report", {})
        artifact = report.get("artifact", {})

        image = artifact.get("repository", "")
        if artifact.get("tag"):
            image = f"{image}:{artifact['tag']}"

        for vuln in report.get("vulnerabilities") or []:
            cve = vuln.get("vulnerabilityID", "")
            if not cve:
                continue
            fixed = vuln.get("fixedVersion") or ""
            yield {
                "cve": cve,
                "severity": (vuln.get("severity") or "UNKNOWN").upper(),
                "namespace": meta.get("namespace", ""),
                "kind": labels.get("trivy-operator.resource.kind", ""),
                "workload": labels.get("trivy-operator.resource.name", ""),
                "container": labels.get("trivy-operator.container.name", ""),
                "image": image,
                "installed_version": vuln.get("installedVersion", ""),
                "fixed_version": fixed,
                "fix_available": bool(fixed),
                "title": vuln.get("title", ""),
                "link": vuln.get("primaryLink", ""),
            }


def priority(item, threshold):
    if item["in_kev"]:
        return "P1"
    if item["epss"] is not None and item["epss"] >= threshold and item["fix_available"]:
        return "P2"
    if item["severity"] in ("CRITICAL", "HIGH") and item["fix_available"]:
        return "P3"
    return "P4"


def sort_key(item):
    return (item["priority"], -(item["epss"] or 0.0), -SEVERITY_RANK.get(item["severity"], 0))


def main():
    ap = argparse.ArgumentParser(description="Rank Trivy findings with EPSS and CISA KEV.")
    ap.add_argument("inputs", nargs="+", help="VulnerabilityReport JSON files")
    ap.add_argument("-o", "--output", default="priorities.csv")
    ap.add_argument("--cache-dir", default="cache", help="where KEV and EPSS data are cached")
    ap.add_argument("--cache-hours", type=float, default=24.0, help="cache lifetime in hours")
    ap.add_argument("--epss-threshold", type=float, default=0.10)
    ap.add_argument("--offline", action="store_true", help="use cached KEV/EPSS data only, no network")
    args = ap.parse_args()

    # Deduplicate: the same CVE in the same container and image is one finding.
    unique = {}
    for path in args.inputs:
        with open(path, encoding="utf-8") as f:
            for item in iter_findings(json.load(f)):
                key = (item["namespace"], item["kind"], item["workload"], item["container"],
                       item["image"], item["cve"], item["installed_version"])
                unique.setdefault(key, item)
    findings = list(unique.values())

    cves = {item["cve"] for item in findings if item["cve"].startswith("CVE-")}
    kev = load_kev(args.cache_dir, args.cache_hours, args.offline)
    epss = load_epss(cves, args.cache_dir, args.cache_hours, args.offline)

    for item in findings:
        item["in_kev"] = item["cve"] in kev
        item["epss"] = epss.get(item["cve"])
        item["priority"] = priority(item, args.epss_threshold)
    findings.sort(key=sort_key)

    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for item in findings:
            row = dict(item)
            row["in_kev"] = "yes" if item["in_kev"] else "no"
            row["fix_available"] = "yes" if item["fix_available"] else "no"
            row["epss"] = "" if item["epss"] is None else f"{item['epss']:.5f}"
            writer.writerow(row)

    counts = {p: 0 for p in ("P1", "P2", "P3", "P4")}
    for item in findings:
        counts[item["priority"]] += 1
    summary = ", ".join(f"{p}: {n}" for p, n in counts.items())
    print(f"{len(findings)} findings written to {args.output} ({summary})", file=sys.stderr)


if __name__ == "__main__":
    main()
