# Proxmox VE: CORE / DMZ VLAN trunks with LACP

**ERNU.EU | IT & Security Solutions** · reusable example, no internal infrastructure addresses published.

Two mutually exclusive installers reproduce a VMware-style port-group structure with two physically separated uplink groups, Cisco Catalyst 3560G LACP, Proxmox SDN zones, and named VNets.

- **Linux Bridge variant**: `install-linux-bridge.sh` — Linux bonding 802.3ad + VLAN-aware bridges.
- **Open vSwitch variant**: `install-ovs.sh` — OVS bridges + LACP OVSBond + tagged internal management port.
- **Cisco template**: `cisco-3560g-lacp.cfg` — Po41 = Gi0/27-28 CORE, Po42 = Gi0/29-30 DMZ, descriptive labels SERVER-101-CORE / SERVER-101-DMZ. Catalyst 3560G supports channel IDs 1–48; Po101/Po102 are invalid.
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
2. For the OVS variant, **before any reboot**, install `openvswitch-switch` while the old management is functional.
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

This implementation is a staging template, not a zero-downtime migration. A manually corrected OVS deployment was validated on 2026-11-24: both bonds negotiated LACP, management reached its gateway and SDN apply preserved the uplinks and management while renaming VLAN 50 to Radio. The updated installer has not yet been tested end-to-end on a fresh node; the subsequent reboot test failed (Po41/Po42 members remained stand-alone after the Cisco mapping was corrected). Root cause on the host is not established; do not treat this as a boot fix. Fresh installation, a successful reboot, failover and VM traffic tests remain pending. Linux Bridge variant remains untested live.
