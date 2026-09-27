#!/usr/bin/env bash
set -Eeuo pipefail

compose_file="${1:-compose.yml}"

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found." >&2; exit 1; }
[[ -f "$compose_file" ]] || { echo "ERROR: $compose_file not found." >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

docker compose -f "$compose_file" config --format json > "$tmp"

python3 - "$tmp" <<'PY'
import json, sys

path=sys.argv[1]
data=json.load(open(path))
services=data.get("services", {})
errors=[]
warnings=[]

def add(bucket, service, message):
    bucket.append(f"{service}: {message}")

for name, svc in services.items():
    if svc.get("privileged") is True:
        add(errors,name,"privileged=true")

    if svc.get("network_mode") == "host":
        add(errors,name,"network_mode=host")

    if svc.get("pid") == "host":
        add(errors,name,"pid=host")

    security=svc.get("security_opt") or []
    if not any(str(x).replace(" ","").lower() == "no-new-privileges:true" for x in security):
        add(warnings,name,"missing no-new-privileges:true")

    drops=[str(x).upper() for x in (svc.get("cap_drop") or [])]
    if "ALL" not in drops:
        add(warnings,name,"cap_drop does not include ALL")

    if not svc.get("read_only", False):
        add(warnings,name,"root filesystem is not read_only")

    if not svc.get("pids_limit"):
        add(warnings,name,"pids_limit not set")

    if not svc.get("healthcheck"):
        add(warnings,name,"healthcheck not defined")

    if str(svc.get("user","")).strip() in ("","0","0:0","root"):
        add(warnings,name,"container user is root/unspecified")

    volumes=svc.get("volumes") or []
    for vol in volumes:
        if isinstance(vol, dict):
            source=str(vol.get("source",""))
            target=str(vol.get("target",""))
            ro=bool(vol.get("read_only",False))
            if source.endswith("docker.sock") or target.endswith("docker.sock"):
                if not ro:
                    add(errors,name,"Docker socket mounted read-write")
                else:
                    add(warnings,name,"Docker socket mounted read-only; still highly privileged")
        elif isinstance(vol, str) and "docker.sock" in vol:
            if vol.endswith(":ro"):
                add(warnings,name,"Docker socket mounted read-only; still highly privileged")
            else:
                add(errors,name,"Docker socket mounted without read-only flag")

print("Compose hardening review")
print("========================")
for name in services:
    print(f"service: {name}")

print()
if errors:
    print("ERRORS:")
    for x in errors: print(f"  - {x}")
else:
    print("ERRORS: none")

print()
if warnings:
    print("WARNINGS:")
    for x in warnings: print(f"  - {x}")
else:
    print("WARNINGS: none")

print()
print(f"summary: errors={len(errors)} warnings={len(warnings)}")

sys.exit(2 if errors else 0)
PY
