# Proxmox VE: CORE / DMZ VLAN trunks with LACP

**ERNU.EU | IT & Security Solutions** · reusable example, no internal infrastructure addresses published.

Four installers (two backends, each with a fixed and an interactive variant; choose exactly one) reproduce a VMware-style port-group structure with two physically separated uplink groups, Cisco Catalyst 3560G LACP, Proxmox SDN zones, and named VNets.

- **Linux Bridge variant**: `install-linux-bridge.sh` — Linux bonding 802.3ad + VLAN-aware bridges.
- **Open vSwitch variant**: `install-ovs.sh` — OVS bridges + LACP OVSBond + tagged internal management port.
- **Cisco template**: `cisco-3560g-lacp.cfg` — Po41 = Gi0/27-28 CORE, Po42 = Gi0/29-30 DMZ, descriptive labels SERVER-101-CORE / SERVER-101-DMZ. Catalyst 3560G supports channel IDs 1–48; Po101/Po102 are invalid.
- **Interactive runbook (RO)**: [docs/INTERACTIVE-INSTALLATION-RO.md](docs/INTERACTIVE-INSTALLATION-RO.md) — all three modes, physical NIC selection, unattended usage, validation and rollback.
- **Runbook**: `docs/IMPLEMENTATION-RO.md` — migration order, validation, recovery.

## Logical design

| Zone | Host ports | Link aggregation | Bridge | VLAN IDs |
|---|---|---|---|---|
| CORE | nic0 + nic1 | bond0, LACP active | vmbr0 | 12,13,20,21,22,25,50,121 |
| DMZ | nic2 + nic3 | bond1, LACP active | vmbr1 | 217,218 |
| Management | through CORE | VLAN-tagged 13 | vmbr0.13 (Linux) / mgmt13 (OVS) | 13 |

Proxmox SDN defines VNet IDs `Radio, CoreMon, CoreVoip, CoreApp, UserLAN, CoreDB, Infra, Mgmt, DMZApp, DMZInfra`. Original VMware names remain in alias fields.

## Preparing on a test node

1. Check the current uplink maps to `nic0`, the other three NICs are present, the existing management connectivity, and the actual physical Cisco switch ports.
2. Both OVS installers detect a missing `openvswitch-switch` package and request approval to install it via APT while the old management is functional. They start and enable the service and verify the OVS database before staging. For unattended installation explicitly set `INSTALL_OVS=yes`; declining or a failed install stops staging. Linux Bridge needs no OVS package.
3. Stage only one variant using real, local values (do not commit values to this public repository):

```bash
MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash install-ovs.sh --install
# OR: MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash install-linux-bridge.sh --install
```

The RFC 5737 addresses above are examples. Scripts do not automatically restart or apply network changes. They update `/etc/network/interfaces`, `/etc/hosts`, and the two SDN config files; backed-up originals are stored under `/root/pve-network-backup-*`.

4. Configure switch Port-Channel41 with CORE VLAN 13 **tagged**, LACP active, and a single minimum active member. Confirm the port-channel can operate with the first host cable alone. Configure Port-Channel42 separately for DMZ. Po40 is reserved for PBS (Gi0/25-26, access VLAN 20); the template does not modify it. Verify group ownership and all members before any change.
5. Restart **only with an out-of-band console or a tested recovery plan**. The management interface will change addresses and will not be reachable until the Cisco trunk negotiates properly.
6. After access is restored, preview SDN via `pvesh get /cluster/sdn/dry-run --node "$(hostname -s)"`, apply from console via `pvesh set /cluster/sdn`, then validate VNets, uplinks, management and VM assignment.

**Not interchangeable:** do not run OVS and Linux Bridge installers one after another or use Linux bonds in OVS bridges.

This implementation is a staging template, not a zero-downtime migration. A manually corrected OVS deployment was validated on 2026-11-24: both bonds negotiated LACP, management reached its gateway and SDN apply preserved the uplinks and management while renaming VLAN 50 to Radio. The updated installer has not yet been tested end-to-end on a fresh node; a subsequent reboot exposed missing automatic interface activation. The operator reports resolution after explicitly adding auto for every physical NIC, in addition to the OVS bridges, bonds and management port; the OVS installer now includes those directives. Fresh-install testing, independent post-reboot log verification, failover and VM traffic tests remain pending. Linux Bridge variant remains untested live.

## Additional interactive installers

The original fixed-topology scripts remain unchanged. Use either new standalone installer:

```bash
bash install-ovs-interactive.sh --install
# OR
bash install-linux-bridge-interactive.sh --install
```

Choose CORE only (8 VNets), DMZ only (2 VNets), or CORE + DMZ (10 VNets). The installer discovers physical Ethernet NICs, displays name/MAC/state/master and requests a comma-separated list for each selected zone. At least two distinct NICs per selected LACP bond are required; names are not hardcoded. CORE uses bond0/vmbr0 and VLAN 13 management; DMZ uses bond1/vmbr1 and preserves existing management when selected alone. CORE migration requires the existing simple vmbr0 uplink to belong to the chosen CORE list. Unselected interface definitions are preserved; existing SDN, pending GUI edits and conflicting NIC configuration require manual reconciliation.

For unattended staging:

```bash
NETWORK_ZONE=core CORE_NICS=eno1,eno2 MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash install-ovs-interactive.sh --install
NETWORK_ZONE=dmz DMZ_NICS=eno3,eno4 bash install-ovs-interactive.sh --install
NETWORK_ZONE=both CORE_NICS=eno1,eno2 DMZ_NICS=eno3,eno4 MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash install-linux-bridge-interactive.sh --install
```

These are fresh-SDN staging installers, not incremental SDN migration tools. Switch port mappings must match the selected NICs; apply only the relevant CORE or DMZ block after verifying group ownership. PBS Po40 remains untouched. No automatic network reload or reboot. The six topology/backend combinations require on-host validation.
