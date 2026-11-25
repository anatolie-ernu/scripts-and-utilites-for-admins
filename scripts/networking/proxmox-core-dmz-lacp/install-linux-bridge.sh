#!/usr/bin/env bash
set -Eeuo pipefail
# ERNU.EU | Proxmox Linux Bridge / LACP / CORE-DMZ
# STAGING ONLY: no ifreload, no reboot, no switch modifications.
# Cisco example: Po41 CORE (Gi0/27-28), Po42 DMZ (Gi0/29-30); never modify reserved PBS Po40.
# Example: MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash "$0" --install
MODE='linux'
NETFILE='/etc/network/interfaces'
SDNDIR='/etc/pve/sdn'
BACKUP="/root/pve-network-backup-$(date +%Y%m%d-%H%M%S)"
fail(){ echo "ERROR: $*" >&2; exit 1; }
[[ "${1:-}" == '--install' ]] || fail 'usage: MGMT_IP=... MGMT_GW=... bash script.sh --install'
[[ $EUID -eq 0 ]] || fail 'run as root'
# Choose the topology before modifying any files.
if [[ -z "${NETWORK_ZONE:-}" ]]; then
    [[ -t 0 ]] || fail 'set NETWORK_ZONE=core, dmz or both for noninteractive use'
    printf '%s\n' 'Select network configuration:' '1) CORE only' '2) DMZ only' '3) CORE + DMZ'
    read -r -p 'Selection [1/2/3]: ' NETWORK_ZONE
fi
case "$NETWORK_ZONE" in
    1|core) NETWORK_ZONE=core; CORE=1; DMZ=0 ;;
    2|dmz) NETWORK_ZONE=dmz; CORE=0; DMZ=1 ;;
    3|both) NETWORK_ZONE=both; CORE=1; DMZ=1 ;;
    *) fail 'invalid selection; choose core, dmz or both' ;;
esac
if (( CORE )); then
    if [[ -t 0 ]]; then
        [[ -n "${MGMT_IP:-}" ]] || read -r -p 'Management IPv4 (VLAN 13): ' MGMT_IP
        [[ -n "${MGMT_GW:-}" ]] || read -r -p 'Management gateway: ' MGMT_GW
    fi
: "${MGMT_IP:?set MGMT_IP as an unused host address}"
: "${MGMT_GW:?set MGMT_GW to the VLAN13 gateway}"
: "${MGMT_VLAN:=13}"
[[ "$MGMT_VLAN" == 13 ]] || fail 'this template is designed for management VLAN 13'
[[ "$MGMT_IP" =~ ^[0-9]+(\.[0-9]+){3}$ && "$MGMT_GW" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || fail 'invalid IPv4 syntax'
python3 - "$MGMT_IP" "$MGMT_GW" <<'PY'
import ipaddress, sys
ip=ipaddress.IPv4Address(sys.argv[1])
gw=ipaddress.IPv4Address(sys.argv[2])
if ip not in ipaddress.IPv4Network(f'{ip}/24', strict=False) or gw not in ipaddress.IPv4Network(f'{ip}/24', strict=False):
    raise SystemExit('gateway not in management /24 subnet')
PY
fi
NICS=()
if (( CORE )); then NICS+=(nic0 nic1); fi
if (( DMZ )); then NICS+=(nic2 nic3); fi
for nic in "${NICS[@]}"; do [[ -e "/sys/class/net/$nic" ]] || fail "missing NIC $nic"; done
for cmd in ifquery ip pvesh python3; do command -v "$cmd" >/dev/null || fail "missing command $cmd"; done
true
[[ -f "$NETFILE" && -d "$SDNDIR" && -w "$SDNDIR" ]] || fail 'network file or writable pmxcfs SDN missing'
[[ ! -s "$SDNDIR/zones.cfg" && ! -s "$SDNDIR/vnets.cfg" ]] || fail 'existing SDN configuration: manual merge required'
# Existing SDN and pending GUI edits require an explicit manual merge.
[[ ! -e /etc/network/interfaces.new ]] || fail 'pending GUI network changes; reconcile manually'
if (( CORE )); then
    grep -Eq '^[[:space:]]*bridge-ports[[:space:]]+nic0[[:space:]]*$' "$NETFILE" || fail 'expected initial management uplink nic0'
fi
if grep -E '^[[:space:]]*(source|source-directory)[[:space:]]+' "$NETFILE" | grep -Ev '^[[:space:]]*source[[:space:]]+/etc/network/interfaces\.d/\*[[:space:]]*$'; then
    fail 'unexpected network include; reconcile manually'
fi
if (( DMZ )); then
    for nic in nic2 nic3; do
        [[ ! -e "/sys/class/net/$nic/master" ]] || fail "$nic already has a master"
        [[ -z "$(ip -o addr show dev "$nic" scope global)" ]] || fail "$nic already has a global IP address"
    done
fi
if [[ -d /etc/network/interfaces.d ]] && grep -RIlE '^[[:space:]]*(auto|iface|mapping|source|source-directory)[[:space:]]+' /etc/network/interfaces.d 2>/dev/null | grep -q .; then
    fail 'interfaces.d contains active definitions; reconcile before migrating'
fi
mkdir -m 0700 -p "$BACKUP"
cp -a "$NETFILE" "$BACKUP/interfaces.before"
cp -a /etc/hosts "$BACKUP/hosts.before"
[[ ! -e /etc/network/interfaces.new ]] || cp -a /etc/network/interfaces.new "$BACKUP/interfaces.new.before"
for f in zones.cfg vnets.cfg; do [[ ! -f "$SDNDIR/$f" ]] || cp -a "$SDNDIR/$f" "$BACKUP/$f.before"; done
ip -br a > "$BACKUP/ip.before.txt"; ip route > "$BACKUP/routes.before.txt"
TMP="$(mktemp /etc/network/.interfaces.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
# Preserve unselected interfaces and existing management in DMZ-only mode.
# Only remove simple manual declarations of selected NICs, plus the original
# single-uplink Linux management bridge when CORE migration is requested.
python3 - "$NETFILE" "$TMP" "$CORE" "$DMZ" <<'PY'
import re, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:3])
core, dmz = (x == "1" for x in sys.argv[3:])
nics = ({"nic0", "nic1"} if core else set()) | ({"nic2", "nic3"} if dmz else set())
targets = nics | ({"vmbr0"} if core else set())
reserved = ({"bond0", "mgmt13", "vmbr0.13"} if core else set()) | ({"bond1", "vmbr1"} if dmz else set())
seen = set()
output = []
removed = None
for line in src.read_text().splitlines(keepends=True):
    code = line.split("#", 1)[0].strip()
    words = code.split()
    if not words:
        output.append(line)
        continue
    head = words[0]
    header = head in ("iface", "auto", "allow-hotplug", "source", "source-directory", "mapping") or head.startswith("allow-")
    if removed and not header:
        if removed in nics:
            raise SystemExit(f"Selected NIC {removed} has options; reconcile manually")
        if head not in ("address", "netmask", "gateway", "bridge-ports", "bridge-stp", "bridge-fd"):
            raise SystemExit(f"Custom management option {head}; reconcile manually")
        if head == "bridge-ports" and words[1:] != ["nic0"]:
            raise SystemExit("Unexpected management uplink")
        continue
    if header:
        removed = None
    if head in ("auto", "allow-hotplug") and targets.intersection(words[1:]):
        remaining = [w for w in words[1:] if w not in targets]
        if remaining:
            output.append(head + " " + " ".join(remaining) + "\n")
        continue
    if head == "iface" and len(words) >= 2 and words[1] in targets:
        name = words[1]
        allowed = [["inet", "manual"]] if name in nics else [["inet", "static"], ["inet", "manual"]]
        if words[2:] not in allowed or name in seen:
            raise SystemExit(f"Unexpected or duplicate stanza for {name}; reconcile manually")
        seen.add(name)
        removed = name
        continue
    # Detect dependencies or conflicting interface definitions outside the removed stanzas.
    for name in targets | reserved:
        if re.search(r"(?<![\w.-])" + re.escape(name) + r"(?![\w-])", code):
            raise SystemExit(f"Interface {name} already referenced; reconcile manually")
    output.append(line)
if core and "vmbr0" not in seen:
    raise SystemExit("Expected initial vmbr0 stanza missing")
dst.write_text("".join(output).rstrip() + "\n")
PY
if (( CORE )); then
    cat >> "$TMP" <<'CONFIG'

auto nic0
iface nic0 inet manual
auto nic1
iface nic1 inet manual

auto bond0
iface bond0 inet manual
    bond-slaves nic0 nic1
    bond-mode 802.3ad
    bond-miimon 100
    bond-lacp-rate fast
    bond-min-links 1
    bond-xmit-hash-policy layer3+4

auto vmbr0
iface vmbr0 inet manual
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 12 13 20 21 22 25 50 121
# CORE

auto vmbr0.13
iface vmbr0.13 inet static
    address @MGMT_IP@/24
    gateway @MGMT_GW@
# Mgmt VLAN 13
CONFIG
fi
if (( DMZ )); then
    cat >> "$TMP" <<'CONFIG'

auto nic2
iface nic2 inet manual
auto nic3
iface nic3 inet manual

auto bond1
iface bond1 inet manual
    bond-slaves nic2 nic3
    bond-mode 802.3ad
    bond-miimon 100
    bond-lacp-rate fast
    bond-min-links 1
    bond-xmit-hash-policy layer3+4

auto vmbr1
iface vmbr1 inet manual
    bridge-ports bond1
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 217 218
# DMZ
CONFIG
fi
if ! grep -Eq '^[[:space:]]*source[[:space:]]+/etc/network/interfaces\.d/\*[[:space:]]*$' "$TMP"; then
    printf '\nsource /etc/network/interfaces.d/*\n' >> "$TMP"
fi
if (( CORE )); then
    sed -i -e "s/@MGMT_IP@/$MGMT_IP/g" -e "s/@MGMT_GW@/$MGMT_GW/g" "$TMP"
fi
ifquery --interfaces "$TMP" --list >/dev/null || fail 'ifquery parse failed'
if (( CORE )); then
# Only edit hostname mapping when an exact current hostname record exists.
python3 - "$MGMT_IP" <<'PY'
import sys
from pathlib import Path
ip=sys.argv[1]
host=Path('/etc/hostname').read_text().strip().split('.')[0]
p=Path('/etc/hosts')
lines=p.read_text().splitlines(keepends=True)
found=False
for i,line in enumerate(lines):
    content,_,comment=line.partition('#')
    words=content.split()
    if len(words)>1 and any(h.split('.')[0]==host for h in words[1:]):
        if found:
            raise SystemExit('multiple host mappings; manual fix required')
        lines[i]=line.replace(words[0],ip,1)
        found=True
if not found: raise SystemExit('hostname mapping not found in /etc/hosts')
p.write_text(''.join(lines))
PY
fi
# Preserve GUI pending file for rollback, remove it so it cannot override staging.
[[ ! -e /etc/network/interfaces.new ]] || mv /etc/network/interfaces.new "$BACKUP/interfaces.new.pending"
install -m 0644 "$TMP" "$NETFILE"
{
    if (( CORE )); then printf 'vlan: CORE\n    bridge vmbr0\n\n'; fi
    if (( DMZ )); then printf 'vlan: DMZ\n    bridge vmbr1\n\n'; fi
} > "$SDNDIR/zones.cfg"
{
    if (( CORE )); then
        cat <<'VNETS'
vnet: Radio
    zone CORE
    alias CORE-RadioMon
    tag 50

vnet: CoreMon
    zone CORE
    alias CORE-Monitoring
    tag 12

vnet: CoreVoip
    zone CORE
    alias CORE-Voip
    tag 25

vnet: CoreApp
    zone CORE
    alias CORE-Application
    tag 21

vnet: UserLAN
    zone CORE
    alias User-LAN
    tag 121

vnet: CoreDB
    zone CORE
    alias CORE-Database
    tag 22

vnet: Infra
    zone CORE
    alias CORE-Infra
    tag 20

vnet: Mgmt
    zone CORE
    alias Mgmt
    tag 13

VNETS
    fi
    if (( DMZ )); then
        cat <<'VNETS'
vnet: DMZApp
    zone DMZ
    alias DMZ-Application
    tag 218

vnet: DMZInfra
    zone DMZ
    alias DMZ-Infrastructure
    tag 217
VNETS
    fi
} > "$SDNDIR/vnets.cfg"
echo "STAGED SUCCESSFULLY: $MODE / $NETWORK_ZONE; backup=$BACKUP"
echo 'No live reload or reboot was performed. Validate selected Cisco LACP/trunks before reboot.'
if (( CORE )); then
    echo "Proxmox management target: https://$MGMT_IP:8006"
else
    echo 'DMZ only: existing management configuration and /etc/hosts preserved.'
fi
echo 'After boot, validate selected LACP bonds and management from the local console.'
echo 'Preview SDN: pvesh get /cluster/sdn/dry-run --node "$(hostname -s)"'
echo 'Apply SDN from console: pvesh set /cluster/sdn; verify uplinks and management again.'
