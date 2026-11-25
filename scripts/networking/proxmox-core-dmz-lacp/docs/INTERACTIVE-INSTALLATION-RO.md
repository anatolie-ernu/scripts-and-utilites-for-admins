# Proxmox VE — Instalare interactivă CORE / DMZ

**ERNU.EU | IT & Security Solutions** · Revizie 2026-11-25

## 1. Alegerea instalatorului

| Script | Tehnologie | Topologie |
|---|---|---|
| install-ovs.sh | Open vSwitch | CORE + DMZ, NIC-uri fixe nic0–nic3 |
| install-linux-bridge.sh | Linux Bridge | CORE + DMZ, NIC-uri fixe nic0–nic3 |
| install-ovs-interactive.sh | Open vSwitch | CORE, DMZ sau ambele, NIC-uri selectate dinamic |
| install-linux-bridge-interactive.sh | Linux Bridge | CORE, DMZ sau ambele, NIC-uri selectate dinamic |

Alege un singur instalator. Cele originale nu au fost înlocuite. Noile scripturi sunt destinate pregătirii unei configurații SDN noi, nu adăugării automate de zone la un cluster deja configurat.

## 2. Topologie

| Zonă | Bond | Bridge | VLAN | VNet-uri |
|---|---|---|---|---|
| CORE | bond0 | vmbr0 | 12,13,20,21,22,25,50,121 | 8 |
| DMZ | bond1 | vmbr1 | 217,218 | 2 |

Managementul CORE utilizează VLAN 13 tagged, cu port mgmt13 în OVS sau vmbr0.13 în Linux Bridge. În DMZ-only, IP-ul, gateway-ul și /etc/hosts existente rămân neschimbate. Nu se creează un IP de management DMZ. Interfețele fizice selectate au auto; se păstrează configurațiile nealese.

| VNet | Alias | VLAN |
|---|---|---:|
| Radio | CORE-RadioMon | 50 |
| CoreMon | CORE-Monitoring | 12 |
| CoreVoip | CORE-Voip | 25 |
| CoreApp | CORE-Application | 21 |
| UserLAN | User-LAN | 121 |
| CoreDB | CORE-Database | 22 |
| Infra | CORE-Infra | 20 |
| Mgmt | Mgmt | 13 |
| DMZApp | DMZ-Application | 218 |
| DMZInfra | DMZ-Infrastructure | 217 |

## 3. Pregătire

Accesul la consola locală/iLO este obligatoriu pentru migrare. Verifică hostname-ul, switch-ul, cablarea și disponibilitatea IP-ului. Pe cluster, SDN este partajat între noduri; nu utiliza scriptul pentru suprascrierea unei configurații existente.

```bash
pveversion
ip -br link
ip -br addr
ip route
cat /etc/network/interfaces
ls -l /etc/network/interfaces.d/
ls -l /etc/pve/sdn/
```

Pentru OVS, scriptul verifică automat pachetul openvswitch-switch. Dacă lipsește, solicită acordul `Install openvswitch-switch and start its service? [y/N]`. La răspuns y execută apt-get update și apt-get install -y openvswitch-switch, pornește serviciul dacă este oprit, îl activează la boot și verifică baza OVS. Refuzul sau o eroare oprește staging-ul. Pentru instalare neinteractivă setează explicit INSTALL_OVS=yes. Managementul existent trebuie să rămână funcțional pe durata instalării APT. Instalatoarele Linux Bridge nu instalează OVS. Necesare: Bash, Python 3, ip, ifquery, pvesh. Scriptul refuză SDN deja definit, modificări GUI pendinte, include-uri neprevăzute și conflicte de interfețe. Pentru CORE, bridge-ul inițial vmbr0 trebuie să fie un Linux Bridge simplu cu un singur uplink inclus în lista CORE. Configurațiile complexe necesită migrare manuală.

## 4. Instalare

```bash
git clone https://github.com/anatolie-ernu/scripts-and-utilites-for-admins.git
cd scripts-and-utilites-for-admins/scripts/networking/proxmox-core-dmz-lacp
bash install-ovs-interactive.sh --install
# SAU (nu ambele)
# bash install-linux-bridge-interactive.sh --install
```

Meniul este în limba engleză:

```text
1) CORE only
2) DMZ only
3) CORE + DMZ
Selection [1/2/3]:
```

După selecție sunt afișate NIC-urile Ethernet fizice detectate: nume, MAC, stare și master. Introdu numele reale separate prin virgulă. Nu introduce bridge-uri, bond-uri, VLAN-uri sau loopback. Sunt necesare cel puțin două NIC-uri distincte pe bond; sunt respinse numele inexistente, duplicatele și suprapunerile între zone.

| Opțiune | Exemplu de răspuns | Management |
|---|---|---|
| 1 — CORE | CORE: eno1,eno2 | Solicită IP și gateway VLAN 13 |
| 2 — DMZ | DMZ: eno3,eno4 | Păstrează configurația existentă |
| 3 — Ambele | CORE: eno1,eno2; DMZ: eno3,eno4 | Solicită IP și gateway VLAN 13 |

Exemplele nu sunt valori obligatorii. Selectează NIC-urile corespunzătoare cablurilor reale. Dacă folosești mai mult de două interfețe, adaptează EtherChannel-ul Cisco; șablonul actual exemplifică doi membri pe zonă. Prefixul de management rămâne /24 conform șablonului. Confirmă cu y la întrebarea de staging după ce verifici selecția. Scriptul nu face ifreload și nu repornește hostul.

### Automatizare neinteractivă

Pentru oricare dintre cele două scripturi interactive, folosește variabilele de mediu de mai jos. Exemplele IP sunt RFC 5737; înlocuiește-le local.

```bash
NETWORK_ZONE=core CORE_NICS=eno1,eno2 MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash install-ovs-interactive.sh --install
NETWORK_ZONE=dmz DMZ_NICS=eno3,eno4 bash install-ovs-interactive.sh --install
NETWORK_ZONE=both CORE_NICS=eno1,eno2 DMZ_NICS=eno3,eno4 MGMT_IP=192.0.2.41 MGMT_GW=192.0.2.1 bash install-ovs-interactive.sh --install
```

Pentru Linux Bridge înlocuiește numele scriptului cu install-linux-bridge-interactive.sh. În mod neinteractiv nu există confirmare suplimentară; rulează numai după verificarea parametrilor.

## 5. Cisco

| Port-channel | Porturi exemplu | Rol |
|---|---|---|
| Po40 | Gi0/25–26 | PBS, ACCESS 20 — nu modifica |
| Po41 | Gi0/27–28 | CORE, trunk 12,13,20-22,25,50,121 |
| Po42 | Gi0/29–30 | DMZ, trunk 217,218 |

Verifică show etherchannel summary și configurațiile active ale porturilor înainte de aplicare. Folosește numai blocul zonei selectate din [șablonul Cisco](../cisco-3560g-lacp.cfg). Confirmă identitatea switch-ului și faptul că grupurile nu aparțin altui echipament. Encapsularea dot1q precedă switchport mode trunk. LACP active pe membrii fizici. Nu modifica Po40 și nu salva Cisco înainte de validare.

## 6. Aplicare și verificare

Examinează /etc/network/interfaces, /etc/pve/sdn/zones.cfg, /etc/pve/sdn/vnets.cfg și backupul raportat. Numai cu consola disponibilă și switch-ul pregătit, activează configurația într-o fereastră de mentenanță. Verifică managementul după restart, apoi:

```bash
pvesh get /cluster/sdn/dry-run --node "$(hostname -s)"
pvesh set /cluster/sdn
ip -br addr
ip route
```

Aplicarea SDN poate afecta rețeaua și alte noduri; verifică domeniul operațiunii înainte de execuție. În GUI: Node → System → Network, Datacenter → SDN → Zones / VNets.

OVS (numai bond-urile selectate):

```bash
ovs-vsctl show
ovs-appctl bond/list
ovs-appctl lacp/show bond0
ovs-appctl lacp/show bond1
```

Linux Bridge (numai bond-urile selectate):

```bash
cat /proc/net/bonding/bond0
cat /proc/net/bonding/bond1
bridge vlan show
```

Pentru CORE verifică și ping către gateway VLAN 13, respectiv acces HTTPS pe portul 8006. Pentru DMZ-only verifică managementul preexistent. Cisco: show etherchannel summary, show lacp neighbor, show interfaces trunk. Port-channel-urile selectate trebuie să fie SU, membrii P; Po40 PBS trebuie să rămână funcțional. Testează VM-urile pe VLAN-urile selectate, failover pe câte un membru și persistența după reboot.

## 7. Recuperare și rollback

Backupurile sunt în directorul /root/pve-network-backup-* afișat de script. În cazul unei erori de staging, nu reporni. Din consola locală, identifică directorul exact și restaurează interfaces.before și, dacă s-a modificat, hosts.before. Restaurează fișierele SDN anterioare dacă existau; dacă nu existau, eliminarea configurației SDN nou create trebuie făcută coordonat, numai dacă nu este utilizată de alte noduri. Nu șterge configurația SDN a clusterului. Revino și la configurația Cisco salvată anterior, fără a modifica PBS. Consultă [ghidul principal](IMPLEMENTATION-RO.md) pentru diagnostic OVS și avertismente ifupdown2.

## 8. Matrice de acceptanță

| Backend | CORE | DMZ | Ambele |
|---|---|---|---|
| OVS interactiv | De testat live | De testat live | De testat live |
| Linux Bridge interactiv | De testat live | De testat live | De testat live |

Remedierea autostart OVS pentru topologia originală a fost confirmată de operator. Nu reprezintă validarea celor șase combinații interactive. Sunt necesare teste pe Proxmox, după restart, cu switch-ul real și trafic VM. Nu publica IP-uri, hostnames interne sau secrete în repository.
