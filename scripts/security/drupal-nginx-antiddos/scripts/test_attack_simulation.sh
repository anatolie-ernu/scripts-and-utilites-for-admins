#!/usr/bin/env bash
# =============================================================================
# test_attack_simulation.sh
# Rulati DOAR pe un mediu de staging propriu, NICIODATA pe productie sau pe
# infrastructura care nu va apartine. Scopul: validati ca lantul
# nginx -> security_log_processor.py -> fail2ban -> nftables functioneaza.
# =============================================================================
set -euo pipefail

TARGET="${1:-https://staging.drupal.ernu.sec}"

if [[ "$TARGET" != https://* ]]; then
    echo "EROARE: tinta trebuie sa foloseasca HTTPS." >&2
    exit 2
fi

read -r -p "Confirmati ca $TARGET este un sistem propriu de staging [scrieti STAGING]: " CONFIRM
if [[ "$CONFIRM" != "STAGING" ]]; then
    echo "Test anulat."
    exit 2
fi

echo "[1/3] Simulez scanare de cai vulnerabile (declanseaza nginx-botsearch)..."
for path in wp-login.php wp-admin/ .env .git/config phpmyadmin/; do
    curl -sk -o /dev/null -w "  %{http_code} $path\n" "$TARGET/$path"
done

echo "[2/3] Simulez bruteforce pe /user/login (declanseaza login_bruteforce)..."
for i in $(seq 1 8); do
    curl -sk -o /dev/null -w "  incercare $i -> %{http_code}\n" \
        -X POST "$TARGET/user/login" -d "name=admin&pass=wrong$i"
done

echo "[3/3] Simulez rafala de cereri (declanseaza limit_req + high_request_rate)..."
for i in $(seq 1 40); do
    curl -sk -o /dev/null -w "%{http_code} " "$TARGET/" &
done
wait
echo

echo "Verificati:"
echo "  tail -f /var/log/nginx/security-alerts.log"
echo "  fail2ban-client status drupal-security-events"
echo "  nft list table inet f2b_drupal_critical"
