#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

input="${1:-logs/events.json}"
[[ -f "$input" ]] || {
  echo "ERROR: event file not found: $input" >&2
  exit 1
}

mkdir -p reports
stamp="$(date '+%Y%m%d_%H%M%S')"
out="reports/falco-summary-$stamp.txt"

python3 - "$input" > "$out" <<'PY'
import collections, json, sys

path=sys.argv[1]
rules=collections.Counter()
priorities=collections.Counter()
total=0
invalid=0

with open(path,encoding="utf-8",errors="replace") as f:
    for line in f:
        line=line.strip()
        if not line:
            continue
        try:
            obj=json.loads(line)
        except Exception:
            invalid+=1
            continue
        total+=1
        rules[obj.get("rule","(unknown)")]+=1
        priorities[obj.get("priority","(unknown)")]+=1

print("ERNU.EU Falco Runtime IDS summary")
print(f"source={path}")
print(f"events={total}")
print(f"invalid_json_lines={invalid}")
print()
print("Priorities:")
for k,v in priorities.most_common():
    print(f"  {k}: {v}")
print()
print("Rules:")
for k,v in rules.most_common():
    print(f"  {v:6d}  {k}")
PY

cat "$out"
echo
echo "REPORT: $out"
