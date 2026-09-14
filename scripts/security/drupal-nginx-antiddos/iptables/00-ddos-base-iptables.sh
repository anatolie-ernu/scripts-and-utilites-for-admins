#!/usr/bin/env bash
# =============================================================================
# 00-ddos-base-iptables.sh
# Echivalentul iptables al nftables/00-ddos-base.nft -- protectie L3/L4:
# SYN flood, ICMP flood, limitare conexiuni concurente per IP sursa.
#
# Rulare:   bash 00-ddos-base-iptables.sh
# Persistenta: netfilter-persistent save   (necesita pachetul iptables-persistent)
# =============================================================================
set -euo pipefail

# --- Conexiuni deja stabilite: acceptate rapid, fara re-evaluare ---
iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -C INPUT -m conntrack --ctstate INVALID -j DROP 2>/dev/null || \
    iptables -I INPUT -m conntrack --ctstate INVALID -j DROP

iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || iptables -I INPUT -i lo -j ACCEPT

# --- SYN flood: limita per IP sursa, nu limita globala a serverului ---
iptables -C INPUT -p tcp --syn -m hashlimit \
    --hashlimit-above 60/second --hashlimit-burst 20 \
    --hashlimit-mode srcip --hashlimit-name syn_per_ip -j DROP 2>/dev/null || \
iptables -A INPUT -p tcp --syn -m hashlimit \
    --hashlimit-above 60/second --hashlimit-burst 20 \
    --hashlimit-mode srcip --hashlimit-name syn_per_ip -j DROP

# --- Semnatura SYN scan clasica (MSS anormal de mic) ---
iptables -C INPUT -p tcp --syn -m tcpmss --mss 1:536 -j DROP 2>/dev/null || \
    iptables -A INPUT -p tcp --syn -m tcpmss --mss 1:536 -j DROP

# --- ICMP flood ---
iptables -C INPUT -p icmp --icmp-type echo-request -m limit --limit 10/second -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 10/second -j ACCEPT
iptables -C INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null || \
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# --- Limiteaza conexiuni concurente NOI per IP sursa catre 80/443 ---
# echivalentul aproximativ al "meter conn-per-ip" din nftables
for PORT in 80 443; do
    iptables -C INPUT -p tcp --dport "$PORT" -m conntrack --ctstate NEW \
        -m connlimit --connlimit-above 100 --connlimit-mask 32 -j DROP 2>/dev/null || \
    iptables -A INPUT -p tcp --dport "$PORT" -m conntrack --ctstate NEW \
        -m connlimit --connlimit-above 100 --connlimit-mask 32 -j DROP
done

echo "Reguli de baza iptables aplicate. Persistati cu: netfilter-persistent save"
