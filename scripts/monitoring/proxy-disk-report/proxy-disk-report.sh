#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

CONFIG_FILE="${CONFIG_FILE:-/etc/sysconfig/proxy-disk-report}"
LOCK_FILE="${LOCK_FILE:-/run/lock/proxy-disk-report.lock}"
HOST_FQDN="$(hostname -f 2>/dev/null || hostname)"
REPORT_DATE="$(date '+%Y-%m-%d %H:%M:%S %Z')"
REPORT_DAY="$(date '+%Y%m%d')"
SENDMAIL_BIN="${SENDMAIL_BIN:-/usr/sbin/sendmail}"

# Defaults may be overridden in /etc/sysconfig/proxy-disk-report.
REPORT_RECIPIENTS="${REPORT_RECIPIENTS:-admin@ernu.eu,reports@ernu.eu}"
REPORT_FROM="${REPORT_FROM:-reports@ernu.eu}"
WARNING_PERCENT="${WARNING_PERCENT:-80}"
CRITICAL_PERCENT="${CRITICAL_PERCENT:-90}"
INCLUDE_VAR_BREAKDOWN="${INCLUDE_VAR_BREAKDOWN:-yes}"

if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

log() {
    logger -t proxy-disk-report -- "$*" 2>/dev/null || true
    printf '%s %s\n' "$(date '+%F %T')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

html_escape() {
    local value="${1-}"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    value="${value//\'/&#39;}"
    printf '%s' "$value"
}

human_bytes() {
    local bytes="${1:-0}"
    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || printf '%sB' "$bytes"
}

validate_config() {
    [[ "$WARNING_PERCENT" =~ ^[0-9]+$ ]] ||
        fail "WARNING_PERCENT must be an integer."
    [[ "$CRITICAL_PERCENT" =~ ^[0-9]+$ ]] ||
        fail "CRITICAL_PERCENT must be an integer."
    (( WARNING_PERCENT > 0 && WARNING_PERCENT < CRITICAL_PERCENT )) ||
        fail "WARNING_PERCENT must be lower than CRITICAL_PERCENT."
    (( CRITICAL_PERCENT <= 100 )) ||
        fail "CRITICAL_PERCENT cannot exceed 100."

    [[ -n "$REPORT_RECIPIENTS" ]] || fail "REPORT_RECIPIENTS is empty."
    [[ -n "$REPORT_FROM" ]] || fail "REPORT_FROM is empty."

    if [[ "$REPORT_RECIPIENTS$REPORT_FROM" == *$'\n'* ||
          "$REPORT_RECIPIENTS$REPORT_FROM" == *$'\r'* ]]; then
        fail "Mail configuration contains an invalid newline."
    fi
}

mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

validate_config

TMP_DIR="$(mktemp -d /tmp/proxy-disk-report.XXXXXX)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

PLAIN_FILE="${TMP_DIR}/body.txt"
HTML_FILE="${TMP_DIR}/disk-usage-${HOST_FQDN}-${REPORT_DAY}.html"
DF_BYTES="${TMP_DIR}/df-bytes.txt"
DF_HUMAN="${TMP_DIR}/df-human.txt"
DF_INODES="${TMP_DIR}/df-inodes.txt"
VAR_USAGE="${TMP_DIR}/var-usage.txt"

df -P -B1 \
    -x tmpfs -x devtmpfs -x squashfs -x overlay \
    > "$DF_BYTES"

df -hP \
    -x tmpfs -x devtmpfs -x squashfs -x overlay \
    > "$DF_HUMAN"

df -iP \
    -x tmpfs -x devtmpfs -x squashfs -x overlay \
    > "$DF_INODES"

MAX_PERCENT=0
MAX_MOUNT="-"
STATUS="OK"

while read -r filesystem blocks used available percent mountpoint; do
    [[ "$filesystem" == "Filesystem" ]] && continue
    usage="${percent%\%}"

    if [[ "$usage" =~ ^[0-9]+$ ]] && (( usage > MAX_PERCENT )); then
        MAX_PERCENT="$usage"
        MAX_MOUNT="$mountpoint"
    fi
done < "$DF_BYTES"

if (( MAX_PERCENT >= CRITICAL_PERCENT )); then
    STATUS="CRITICAL"
elif (( MAX_PERCENT >= WARNING_PERCENT )); then
    STATUS="WARNING"
fi

if [[ "$INCLUDE_VAR_BREAKDOWN" == "yes" && -d /var ]]; then
    timeout 180s du -x -B1 --max-depth=1 /var 2>/dev/null |
        sort -nr |
        head -n 20 > "$VAR_USAGE" || true
fi

{
    printf 'Daily disk usage report\n'
    printf '=======================\n\n'
    printf 'Server: %s\n' "$HOST_FQDN"
    printf 'Generated: %s\n' "$REPORT_DATE"
    printf 'Overall status: %s\n' "$STATUS"
    printf 'Highest usage: %s%% on %s\n' "$MAX_PERCENT" "$MAX_MOUNT"
    printf 'Thresholds: warning >= %s%%, critical >= %s%%\n\n' \
        "$WARNING_PERCENT" "$CRITICAL_PERCENT"

    printf 'Filesystem capacity\n'
    printf '%s\n' '-------------------'
    cat "$DF_HUMAN"

    printf '\nInode capacity\n'
    printf '%s\n' '--------------'
    cat "$DF_INODES"

    if [[ -s "$VAR_USAGE" ]]; then
        printf '\nLargest top-level directories under /var\n'
        printf '%s\n' '----------------------------------------'
        while read -r bytes path; do
            printf '%10s  %s\n' "$(human_bytes "$bytes")" "$path"
        done < "$VAR_USAGE"
    fi

    printf '\nThis message was generated automatically by %s.\n' "$HOST_FQDN"
} > "$PLAIN_FILE"

case "$STATUS" in
    CRITICAL)
        STATUS_COLOR="#b91c1c"
        STATUS_BG="#fee2e2"
        ;;
    WARNING)
        STATUS_COLOR="#b45309"
        STATUS_BG="#fef3c7"
        ;;
    *)
        STATUS_COLOR="#166534"
        STATUS_BG="#dcfce7"
        ;;
esac

{
    printf '%s\n' '<!doctype html>'
    printf '%s\n' '<html lang="en"><head><meta charset="utf-8">'
    printf '%s\n' '<meta name="viewport" content="width=device-width, initial-scale=1">'
    printf '%s\n' '<title>Proxy disk usage report</title>'
    printf '%s\n' '<style>'
    printf '%s\n' 'body{font-family:Arial,sans-serif;background:#f3f4f6;color:#111827;margin:0;padding:24px}'
    printf '%s\n' '.card{max-width:1100px;margin:auto;background:white;border-radius:12px;padding:24px;box-shadow:0 2px 10px #0002}'
    printf '%s\n' 'h1,h2{color:#1f2937}table{border-collapse:collapse;width:100%;margin:12px 0 24px}'
    printf '%s\n' 'th,td{border:1px solid #d1d5db;padding:8px;text-align:left}th{background:#e5e7eb}'
    printf '%s\n' '.ok{background:#dcfce7;color:#166534}.warning{background:#fef3c7;color:#b45309}.critical{background:#fee2e2;color:#b91c1c}'
    printf '%s\n' '.badge{display:inline-block;padding:7px 12px;border-radius:999px;font-weight:bold}'
    printf '%s\n' '.meta{color:#4b5563}.bar{height:16px;background:#e5e7eb;border-radius:8px;overflow:hidden;min-width:130px}'
    printf '%s\n' '.fill{height:100%}.footer{font-size:12px;color:#6b7280;margin-top:24px}'
    printf '%s\n' '</style></head><body><div class="card">'

    printf '<h1>Daily disk usage report</h1>\n'
    printf '<p class="meta"><strong>Server:</strong> %s<br><strong>Generated:</strong> %s</p>\n' \
        "$(html_escape "$HOST_FQDN")" "$(html_escape "$REPORT_DATE")"
    printf '<p><span class="badge" style="color:%s;background:%s">%s — maximum %s%% on %s</span></p>\n' \
        "$STATUS_COLOR" "$STATUS_BG" "$STATUS" "$MAX_PERCENT" "$(html_escape "$MAX_MOUNT")"

    printf '%s\n' '<h2>Filesystem capacity</h2>'
    printf '%s\n' '<table><thead><tr><th>Filesystem</th><th>Size</th><th>Used</th><th>Available</th><th>Usage</th><th>Mount</th><th>Visual</th></tr></thead><tbody>'

    while read -r filesystem blocks used available percent mountpoint; do
        [[ "$filesystem" == "Filesystem" ]] && continue
        usage="${percent%\%}"
        css_class="ok"
        row_color="#22c55e"
        if (( usage >= CRITICAL_PERCENT )); then
            css_class="critical"
            row_color="#dc2626"
        elif (( usage >= WARNING_PERCENT )); then
            css_class="warning"
            row_color="#f59e0b"
        fi

        printf '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><strong>%s</strong></td><td>%s</td><td><div class="bar"><div class="fill" style="width:%s;background:%s"></div></div></td></tr>\n' \
            "$css_class" \
            "$(html_escape "$filesystem")" \
            "$(human_bytes "$blocks")" \
            "$(human_bytes "$used")" \
            "$(human_bytes "$available")" \
            "$(html_escape "$percent")" \
            "$(html_escape "$mountpoint")" \
            "$percent" "$row_color"
    done < "$DF_BYTES"

    printf '%s\n' '</tbody></table>'
    printf '%s\n' '<h2>Inode capacity</h2><table><thead><tr><th>Filesystem</th><th>Inodes</th><th>Used</th><th>Free</th><th>Usage</th><th>Mount</th></tr></thead><tbody>'

    while read -r filesystem inodes iused ifree ipercent mountpoint; do
        [[ "$filesystem" == "Filesystem" ]] && continue
        printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
            "$(html_escape "$filesystem")" \
            "$(html_escape "$inodes")" \
            "$(html_escape "$iused")" \
            "$(html_escape "$ifree")" \
            "$(html_escape "$ipercent")" \
            "$(html_escape "$mountpoint")"
    done < "$DF_INODES"

    printf '%s\n' '</tbody></table>'

    if [[ -s "$VAR_USAGE" ]]; then
        printf '%s\n' '<h2>Largest top-level directories under /var</h2>'
        printf '%s\n' '<table><thead><tr><th>Size</th><th>Path</th></tr></thead><tbody>'
        while read -r bytes path; do
            printf '<tr><td>%s</td><td>%s</td></tr>\n' \
                "$(human_bytes "$bytes")" "$(html_escape "$path")"
        done < "$VAR_USAGE"
        printf '%s\n' '</tbody></table>'
    fi

    printf '<p class="footer">Thresholds: warning ≥ %s%%, critical ≥ %s%%. Generated automatically by %s.</p>\n' \
        "$WARNING_PERCENT" "$CRITICAL_PERCENT" "$(html_escape "$HOST_FQDN")"
    printf '%s\n' '</div></body></html>'
} > "$HTML_FILE"

SUBJECT="[$STATUS] Disk usage ${HOST_FQDN}: ${MAX_PERCENT}% on ${MAX_MOUNT}"

if [[ "${1:-}" == "--dry-run" ]]; then
    cat "$PLAIN_FILE"
    printf '\nHTML report generated temporarily at: %s\n' "$HTML_FILE"
    exit 0
fi

[[ -x "$SENDMAIL_BIN" ]] ||
    fail "sendmail interface not found at $SENDMAIL_BIN. Install/configure Postfix first."

MIXED_BOUNDARY="=_disk_mixed_$(date +%s)_$$"
ALT_BOUNDARY="=_disk_alternative_$(date +%s)_$$"
ATTACHMENT_NAME="$(basename "$HTML_FILE")"

{
    printf 'From: %s\n' "$REPORT_FROM"
    printf 'To: %s\n' "$REPORT_RECIPIENTS"
    printf 'Subject: %s\n' "$SUBJECT"
    printf 'Date: %s\n' "$(LC_ALL=C date -R)"
    printf 'MIME-Version: 1.0\n'
    printf 'Content-Type: multipart/mixed; boundary="%s"\n' \
        "$MIXED_BOUNDARY"
    printf '\n'

    # Multipart alternative: plain-text fallback and rich inline HTML.
    printf -- '--%s\n' "$MIXED_BOUNDARY"
    printf 'Content-Type: multipart/alternative; boundary="%s"\n\n' \
        "$ALT_BOUNDARY"

    printf -- '--%s\n' "$ALT_BOUNDARY"
    printf 'Content-Type: text/plain; charset=UTF-8\n'
    printf 'Content-Transfer-Encoding: 8bit\n\n'
    cat "$PLAIN_FILE"
    printf '\n'

    printf -- '--%s\n' "$ALT_BOUNDARY"
    printf 'Content-Type: text/html; charset=UTF-8\n'
    printf 'Content-Transfer-Encoding: 8bit\n'
    printf 'Content-Disposition: inline\n\n'
    cat "$HTML_FILE"
    printf '\n'

    printf -- '--%s--\n' "$ALT_BOUNDARY"

    # Attach the same colored HTML report as a standalone file.
    printf -- '--%s\n' "$MIXED_BOUNDARY"
    printf 'Content-Type: text/html; charset=UTF-8; name="%s"\n' "$ATTACHMENT_NAME"
    printf 'Content-Disposition: attachment; filename="%s"\n' "$ATTACHMENT_NAME"
    printf 'Content-Transfer-Encoding: base64\n\n'
    base64 -w 76 "$HTML_FILE"
    printf '\n'

    printf -- '--%s--\n' "$MIXED_BOUNDARY"
} | "$SENDMAIL_BIN" -t -oi

log "Disk report sent to $REPORT_RECIPIENTS; status=$STATUS; maximum=${MAX_PERCENT}% on $MAX_MOUNT"
