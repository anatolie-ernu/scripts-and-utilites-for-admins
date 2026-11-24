# Ghid de implementare — Proxmox CORE / DMZ + Cisco 3560G

## Scop
Reproducerea logică a port group-urilor VMware pe Proxmox VE cu două trunk-uri fizice agregate separat în LACP. Sunt disponibile variante Linux Bridge și Open vSwitch, însă **se alege una singură**.

## Porturi și VLAN-uri
- CORE: nic0 + nic1, bond0, vmbr0; VLAN 12/13/20/21/22/25/50/121; management tagged VLAN 13.
- DMZ: nic2 + nic3, bond1, vmbr1; VLAN 217/218; fără IP de management al hypervisorului.
- Cisco: Po40 CORE (Gi0/27 → nic0, Gi0/28 → nic1), Po41 DMZ (Gi0/29 → nic2, Gi0/30 → nic3); două EtherChannel-uri independente. Verifică fizic corespondența înainte de aplicare. **Cisco Catalyst 3560G acceptă EtherChannel 1–48; Po101/Po102 nu sunt valide.** Identificatorul SERVER-101 este păstrat în descrierile porturilor/Port-Channel-urilor.
- La început este conectat un singur cablu CORE. LACP poate opera cu un membru dacă atât hostul cât și switchul acceptă acest lucru. DMZ rămâne fără uplink până la conectarea cablurilor.

## Inventar SDN
| VNet | Alias VMware | VLAN | Zone |
|---|---|---:|---|
| CoreRdio | CORE-RadioMon | 50 | CORE |
| CoreMon | CORE-Monitoring | 12 | CORE |
| CoreVoip | CORE-Voip | 25 | CORE |
| CoreApp | CORE-Application | 21 | CORE |
| UserLAN | User-LAN | 121 | CORE |
| CoreDB | CORE-Database | 22 | CORE |
| Infra | CORE-Infra | 20 | CORE |
| Mgmt | Mgmt | 13 | CORE |
| DMZApp | DMZ-Application | 218 | DMZ |
| DMZInfra | DMZ-Infrastructure | 217 | DMZ |

Identificatorii VNet sunt max. 8 caractere. Denumirile VMware lungi sunt păstrate în alias, nu în numele interfețelor Linux.

## Preflight
Execută read-only:
```bash
hostname -s
pveversion
ip -br address
ip route
cat /etc/network/interfaces
test ! -e /etc/network/interfaces.new || cat /etc/network/interfaces.new
ls -l /etc/network/interfaces.d/
find /etc/pve/sdn -maxdepth 1 -type f -print
```

Pe Cisco: `show interfaces status`, `show etherchannel summary`, `show running-config interface GigabitEthernet0/27` (repetă pentru Gi0/28, Gi0/29, Gi0/30), `show interfaces trunk`, `show vlan brief`. Verifică VLAN 13 existent și rutabil către gateway. Confirmă că nu suprascrii Port-Channel-uri existente.

## Migrare recomandată
1. Confirmă IP-ul nou liber, gateway-ul și accesul la consolă/iLO. Portul switch-ului în ACCESS și IP-ul hostului vechi **vor înceta să funcționeze** după trecere.
2. Instalează `openvswitch-switch` numai pentru varianta OVS, în timp ce rețeaua veche este operațională.
3. Pregătește configurația: `MGMT_IP=<IP> MGMT_GW=<IP_GW> bash install-ovs.sh --install` sau `install-linux-bridge.sh`. Instalatorul scrie fișiere și backup; **nu** execută ifreload/reboot.
4. Revizuiește fișierul `/etc/network/interfaces`, `/etc/hosts`, `/etc/pve/sdn/zones.cfg`, `/etc/pve/sdn/vnets.cfg`. În special, confirmă că nu există interfețe personalizate în `interfaces.d`.
5. Pregătește Cisco Po40 și LACP active pe portul real conectat la nic0. Native VLAN nu trebuie să fie 13. Configurează allowed VLAN list exact. Cisco 3560G cu encapsularea implicită `Auto` respinge `switchport mode trunk`; configurează obligatoriu `switchport trunk encapsulation dot1q` înainte de `switchport mode trunk` atât pe Po40/Po41, cât și pe Gi0/27–30. Dacă interfețele sunt deja membre EtherChannel și IOS refuză modificarea, verifică configurația înainte de a scoate membrii din channel-group.
6. Repornește hostul **numai** când ești pregătit să comuți Cisco și să intervii la consolă dacă este necesar. Așteaptă reconvergența LACP. Nu presupune că restartul hostului este sigur dacă lipsește accesul out-of-band.
7. Verifică accesul HTTPS la noul IP și conectivitatea gatewayului.
8. Aplică SDN cu `pvesh set /cluster/sdn`. Confirmă în Datacenter → SDN → Zones/VNets.
9. Conectează porturile secundare, verifică active links și testează failover (un membru deconectat, fără oprirea managementului).

## STP PortFast trunk și BPDU Guard — configurate pe Po40 și Po41

Pe switch au fost aplicate următoarele comenzi (starea operativă se verifică după conectarea cablurilor):

```text
interface Port-channel40
 spanning-tree portfast trunk
 spanning-tree bpduguard enable
interface Port-channel41
 spanning-tree portfast trunk
 spanning-tree bpduguard enable
```

- **PortFast trunk** scurtează tranziția STP spre forwarding pentru un server conectat la marginea rețelei. Nu îl folosi pentru conexiuni între switch-uri sau în prezența unor punți L2 necontrolate.
- **BPDU Guard** poate pune interfața în `err-disabled` dacă recepționează BPDU-uri. Este util doar când hypervisorul este un endpoint fără STP/RSTP activ și nu retransmite BPDU-uri.
- În cazul OVS: verifică faptul că STP și RSTP sunt dezactivate pe `vmbr0` și `vmbr1`. Nu conecta cele două bridge-uri unul la altul.
- Pentru prima validare se poate dezactiva temporar BPDU Guard, fără a elimina PortFast:

```text
configure terminal
interface Port-channel40
 no spanning-tree bpduguard enable
exit
interface Port-channel41
 no spanning-tree bpduguard enable
exit
end
```

După verificarea cablării, LACP, absenței BPDU-urilor și a stării STP, poți reactiva controlul explicit. Nu salva configurația finală până nu verifici că porturile nu sunt `err-disabled`.

Verificare read-only:

```text
show spanning-tree interface port-channel 40 detail
show spanning-tree interface port-channel 41 detail
show interfaces status err-disabled
show etherchannel summary
show lacp neighbor
```

## Validare
Linux Bridge:
```bash
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1
bridge vlan show
ip -br address
```
OVS:
```bash
ovs-vsctl show
ovs-appctl bond/show bond0
ovs-appctl lacp/show bond0
ovs-appctl bond/show bond1
ip -br address
```
Cisco:
```text
show etherchannel summary
show lacp neighbor
show interfaces trunk
show mac address-table vlan 13
```

## Rollback
- Backupurile sunt sub `/root/pve-network-backup-YYYYMMDD-HHMMSS`. Notează directorul exact raportat de installer.
- Cu acces la consolă, restaurează `interfaces.before` în `/etc/network/interfaces` și `hosts.before` în `/etc/hosts`. Dacă există, restaurează și `interfaces.new.before`.
- În cazul unui SDN nou, revino la fișierele `zones.cfg` și `vnets.cfg` anterioare; pe cluster nu șterge definiții întrebuințate de alte noduri.
- Readu portul Cisco la configurația **salvată anterior** (nu presupune că revertirea fișierului de pe host restabilește accesul dacă switchul rămâne LACP TRUNK).
- Aplică rețeaua prin consola locală, confirmă IP/gateway și numai apoi salvează configurațiile Cisco.

## Limitări și securitate
- Conectivitatea CORE și DMZ este separată fizic. Comunicarea inter-zonă se controlează prin router/firewall; două bridges nu constituie singure un firewall.
- LACP pe 3560G poate pierde trafic scurt la convergență; un singur flow nu agregă liniar viteza ambelor porturi.
- Validarea sintactică nu înlocuiește un test live pe modelul exact de switch și pe versiunea Proxmox.
- Repository-ul public nu conține hostnames/IP-uri interne reale, parole sau secrete.
