#!/usr/bin/env bash
set -Eeuo pipefail
# ERNU.EU | Proxmox Open vSwitch / LACP / CORE-DMZ
# STAGING ONLY: no ifreload, no reboot, no switch modifications.
# Cisco example: Po41 CORE (Gi0/27-28), Po42 DMZ (Gi0/29-30); never modify reserved PBS Po40.
# Example: MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash "$0" --install
MODE='ovs'
NETFILE='/etc/network/interfaces'
SDNDIR='/etc/pve/sdn'
BACKUP="/root/pve-network-backup-$(date +%Y%m%d-%H%M%S)"
fail(){ echo "ERROR: $*" >&2; exit 1; }
[[ "${1:-}" == '--install' ]] || fail 'usage: MGMT_IP=... MGMT_GW=... bash script.sh --install'
[[ $EUID -eq 0 ]] || fail 'run as root'
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
for nic in nic0 nic1 nic2 nic3; do [[ -e "/sys/class/net/$nic" ]] || fail "missing NIC $nic"; done
for cmd in ifquery ip pvesh python3; do command -v "$cmd" >/dev/null || fail "missing command $cmd"; done
command -v ovs-vsctl >/dev/null || fail 'install openvswitch-switch before staging'
dpkg-query -W -f='${Status}' openvswitch-switch 2>/dev/null | grep -q 'install ok installed' || fail 'install openvswitch-switch first'
[[ -f "$NETFILE" && -d "$SDNDIR" && -w "$SDNDIR" ]] || fail 'network file or writable pmxcfs SDN missing'
[[ ! -s "$SDNDIR/zones.cfg" && ! -s "$SDNDIR/vnets.cfg" ]] || fail 'existing SDN configuration: manual merge required'
for file in "$NETFILE" /etc/network/interfaces.new; do
    [[ -f "$file" ]] || continue
    grep -Eq '^[[:space:]]*bridge-ports[[:space:]]+nic0[[:space:]]*$' "$file" || fail "unexpected uplink in $file"
    if grep -Eq '^[[:space:]]*(iface|auto)[[:space:]]+(bond[01]|vmbr1|mgmt13|vmbr0\.13)([[:space:]]|$)' "$file"; then
        fail "already migrated or contains network definitions to review: $file"
    fi
    if grep -E '^[[:space:]]*(source|source-directory)[[:space:]]+' "$file" | grep -Ev '^[[:space:]]*source[[:space:]]+/etc/network/interfaces\.d/\*[[:space:]]*$'; then
        fail "unexpected include in $file"
    fi
done
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
cat > "$TMP" <<'CONFIG'
auto lo
iface lo inet loopback

iface nic0 inet manual
iface nic1 inet manual
iface nic2 inet manual
iface nic3 inet manual

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
    ovs_bonds nic0 nic1
    ovs_options bond_mode=balance-tcp lacp=active other_config:lacp-time=fast trunks=12,13,20,21,22,25,50,121

auto mgmt13
allow-vmbr0 mgmt13
iface mgmt13 inet static
    address @MGMT_IP@/24
    gateway @MGMT_GW@
    ovs_type OVSIntPort
    ovs_bridge vmbr0
    ovs_options tag=13

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
    ovs_bonds nic2 nic3
    ovs_options bond_mode=balance-tcp lacp=active other_config:lacp-time=fast trunks=217,218

source /etc/network/interfaces.d/*
CONFIG
sed -i -e "s/@MGMT_IP@/$MGMT_IP/g" -e "s/@MGMT_GW@/$MGMT_GW/g" "$TMP"
ifquery --interfaces "$TMP" --list >/dev/null || fail 'ifquery parse failed'
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
# Preserve GUI pending file for rollback, remove it so it cannot override staging.
[[ ! -e /etc/network/interfaces.new ]] || mv /etc/network/interfaces.new "$BACKUP/interfaces.new.pending"
install -m 0644 "$TMP" "$NETFILE"
cat > "$SDNDIR/zones.cfg" <<'ZONES'
vlan: CORE
    bridge vmbr0

vlan: DMZ
    bridge vmbr1
ZONES
cat > "$SDNDIR/vnets.cfg" <<'VNETS'
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

vnet: DMZApp
    zone DMZ
    alias DMZ-Application
    tag 218

vnet: DMZInfra
    zone DMZ
    alias DMZ-Infrastructure
    tag 217
VNETS
echo "STAGED SUCCESSFULLY: $MODE; backup=$BACKUP"
echo 'No live reload or reboot was performed. Validate Cisco LACP/trunks before reboot.'
echo 'WARNING: OVS boot persistence is not yet validated; use local console and the recovery runbook.'
echo "Proxmox management target: https://$MGMT_IP:8006"
echo 'After management is back, verify both LACP bonds and gateway from console.'
echo 'Preview SDN: pvesh get /cluster/sdn/dry-run --node "$(hostname -s)"'
echo 'Apply SDN from console: pvesh set /cluster/sdn; verify uplinks and management again.'
