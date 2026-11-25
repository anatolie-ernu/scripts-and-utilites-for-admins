#!/usr/bin/env bash
set -Eeuo pipefail
# ERNU.EU | Proxmox Open vSwitch / LACP / CORE-DMZ
# STAGING ONLY: no ifreload, no reboot, no switch modifications.
# Cisco example: Po41 CORE (Gi0/27-28), Po42 DMZ (Gi0/29-30); never modify reserved PBS Po40.
# Example: NETWORK_ZONE=both CORE_NICS=eno1,eno2 DMZ_NICS=eno3,eno4 MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash "$0" --install
MODE='ovs'
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
# Discover physical Ethernet interfaces only.
declare -A AVAILABLE=() SELECTED=()
CORE_PORTS=(); DMZ_PORTS=()
printf '\n%-16s %-18s %-10s %s\n' INTERFACE MAC STATE MASTER
for dev in /sys/class/net/*; do
    [[ -e "$dev/device" && "$(cat "$dev/type")" == 1 && ! -d "$dev/wireless" && ! -e "$dev/phy80211" ]] || continue
    nic="${dev##*/}"
    [[ "$nic" =~ ^[a-zA-Z0-9_-]{1,15}$ ]] || continue
    AVAILABLE["$nic"]=1
    master=-
    if [[ -L "$dev/master" ]]; then master="$(basename "$(readlink "$dev/master")")"; fi
    printf '%-16s %-18s %-10s %s\n' "$nic" "$(cat "$dev/address")" "$(cat "$dev/operstate")" "$master"
done
(( ${#AVAILABLE[@]} > 0 )) || fail 'no physical Ethernet interfaces detected'
select_ports() {
    local zone="$1" raw="$2" nic
    local -n ports="$3"
    if [[ -z "$raw" ]]; then
        [[ -t 0 ]] || fail "set ${zone}_NICS to a comma-separated list"
        read -r -p "$zone interfaces (comma separated): " raw
    fi
    raw="${raw//[[:space:]]/}"
    [[ "$raw" =~ ^[a-zA-Z0-9_-]+(,[a-zA-Z0-9_-]+)+$ ]] || fail "$zone requires at least two physical NICs separated by commas"
    IFS=, read -r -a ports <<< "$raw"
    for nic in "${ports[@]}"; do
        [[ -n "${AVAILABLE[$nic]:-}" ]] || fail "unknown or nonphysical NIC: $nic"
        [[ -z "${SELECTED[$nic]:-}" ]] || fail "duplicate NIC or overlap between zones: $nic"
        SELECTED["$nic"]="$zone"
    done
}
if (( CORE )); then select_ports CORE "${CORE_NICS:-}" CORE_PORTS; fi
if (( DMZ )); then select_ports DMZ "${DMZ_NICS:-}" DMZ_PORTS; fi
CORE_MEMBERS="${CORE_PORTS[*]}"
DMZ_MEMBERS="${DMZ_PORTS[*]}"
printf '\nSelected topology: %s\n' "$NETWORK_ZONE"
if (( CORE )); then printf 'CORE: %s\n' "$CORE_MEMBERS"; fi
if (( DMZ )); then printf 'DMZ: %s\n' "$DMZ_MEMBERS"; fi
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
for cmd in ifquery ip pvesh python3; do command -v "$cmd" >/dev/null || fail "missing command $cmd"; done
command -v ovs-vsctl >/dev/null || fail 'install openvswitch-switch before staging'
dpkg-query -W -f='${Status}' openvswitch-switch 2>/dev/null | grep -q 'install ok installed' || fail 'install openvswitch-switch first'
[[ -f "$NETFILE" && -d "$SDNDIR" && -w "$SDNDIR" ]] || fail 'network file or writable pmxcfs SDN missing'
[[ ! -s "$SDNDIR/zones.cfg" && ! -s "$SDNDIR/vnets.cfg" ]] || fail 'existing SDN configuration: manual merge required'
# Existing SDN and pending GUI edits require an explicit manual merge.
[[ ! -e /etc/network/interfaces.new ]] || fail 'pending GUI network changes; reconcile manually'
if grep -E '^[[:space:]]*(source|source-directory)[[:space:]]+' "$NETFILE" | grep -Ev '^[[:space:]]*source[[:space:]]+/etc/network/interfaces\.d/\*[[:space:]]*$'; then
    fail 'unexpected network include; reconcile manually'
fi
if (( DMZ )); then
    for nic in "${DMZ_PORTS[@]}"; do
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
python3 - "$NETFILE" "$TMP" "$CORE" "$DMZ" "$CORE_MEMBERS" "$DMZ_MEMBERS" <<'PY'
import re, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:3])
core, dmz = (x == "1" for x in sys.argv[3:5])
core_ports, dmz_ports = map(lambda x: set(x.split()), sys.argv[5:7])
nics = core_ports | dmz_ports
management_uplink = None
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
        if head == "bridge-ports":
            if management_uplink is not None or len(words) != 2 or words[1] not in core_ports:
                raise SystemExit("Existing vmbr0 must have one uplink selected in CORE")
            management_uplink = words[1]
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
if core and ("vmbr0" not in seen or management_uplink is None):
    raise SystemExit("Expected initial vmbr0 stanza and selected management uplink missing")
dst.write_text("".join(output).rstrip() + "\n")
PY
if (( CORE )); then
    for nic in "${CORE_PORTS[@]}"; do
        printf '\nauto %s\niface %s inet manual\n' "$nic" "$nic" >> "$TMP"
    done
    cat >> "$TMP" <<'CONFIG'

auto vmbr0
iface vmbr0 inet manual
    ovs_type OVSBridge
    ovs_ports bond0 mgmt13
# CORE

auto bond0
allow-vmbr0 bond0
iface bond0 inet manual
    ovs_type OVSBond
    ovs_bridge vmbr0
    ovs_bonds @CORE_MEMBERS@
    ovs_options bond_mode=balance-tcp lacp=active other_config:lacp-time=fast trunks=12,13,20,21,22,25,50,121

auto mgmt13
allow-vmbr0 mgmt13
iface mgmt13 inet static
    address @MGMT_IP@/24
    gateway @MGMT_GW@
    ovs_type OVSIntPort
    ovs_bridge vmbr0
    ovs_options tag=13
CONFIG
fi
if (( DMZ )); then
    for nic in "${DMZ_PORTS[@]}"; do
        printf '\nauto %s\niface %s inet manual\n' "$nic" "$nic" >> "$TMP"
    done
    cat >> "$TMP" <<'CONFIG'

auto vmbr1
iface vmbr1 inet manual
    ovs_type OVSBridge
    ovs_ports bond1
# DMZ

auto bond1
allow-vmbr1 bond1
iface bond1 inet manual
    ovs_type OVSBond
    ovs_bridge vmbr1
    ovs_bonds @DMZ_MEMBERS@
    ovs_options bond_mode=balance-tcp lacp=active other_config:lacp-time=fast trunks=217,218
CONFIG
fi
if ! grep -Eq '^[[:space:]]*source[[:space:]]+/etc/network/interfaces\.d/\*[[:space:]]*$' "$TMP"; then
    printf '\nsource /etc/network/interfaces.d/*\n' >> "$TMP"
fi
if (( CORE )); then
    sed -i -e "s/@MGMT_IP@/$MGMT_IP/g" -e "s/@MGMT_GW@/$MGMT_GW/g" "$TMP"
fi
sed -i -e "s/@CORE_MEMBERS@/$CORE_MEMBERS/g" -e "s/@DMZ_MEMBERS@/$DMZ_MEMBERS/g" "$TMP"
ifquery --interfaces "$TMP" --list >/dev/null || fail 'ifquery parse failed'
if [[ -t 0 ]]; then
    read -r -p 'Stage these settings (no live reload)? [y/N]: ' confirm
    [[ "$confirm" == y || "$confirm" == Y ]] || fail 'cancelled'
fi
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
