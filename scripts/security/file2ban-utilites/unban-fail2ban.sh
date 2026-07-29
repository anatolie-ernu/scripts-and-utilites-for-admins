#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly FAIL2BAN_CLIENT="${FAIL2BAN_CLIENT:-/usr/bin/fail2ban-client}"

pause() {
    read -r -p "Press ENTER to return to the menu..." _
}

require_root() {
    if (( EUID != 0 )); then
        printf 'ERROR: Run this utility as root.\n' >&2
        exit 1
    fi
}

require_fail2ban() {
    if [[ ! -x "$FAIL2BAN_CLIENT" ]]; then
        printf 'ERROR: fail2ban-client was not found at %s.\n' "$FAIL2BAN_CLIENT" >&2
        exit 1
    fi

    if ! "$FAIL2BAN_CLIENT" ping >/dev/null 2>&1; then
        printf 'ERROR: Fail2Ban is not running or its socket is unavailable.\n' >&2
        exit 1
    fi
}

get_jails() {
    "$FAIL2BAN_CLIENT" status |
        awk -F: '/Jail list/ {gsub(/,/, " ", $2); gsub(/^[[:space:]]+/, "", $2); print $2}'
}

get_banned_ips() {
    local jail="$1"
    "$FAIL2BAN_CLIENT" status "$jail" |
        awk -F: '/Banned IP list/ {sub(/^[[:space:]]+/, "", $2); print $2}'
}

list_banned() {
    local jail ips
    printf '\n%-28s %s\n' "JAIL" "BANNED IP ADDRESSES"
    printf '%-28s %s\n' "----------------------------" "------------------------------"

    for jail in $(get_jails); do
        ips="$(get_banned_ips "$jail")"
        printf '%-28s %s\n' "$jail" "${ips:-(none)}"
    done
    printf '\n'
    pause
}

valid_ip() {
    local value="$1"
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$value" == *:* ]]
}

unban_ip() {
    local ip jail result=0
    read -r -p "IP address to unban: " ip

    if [[ -z "$ip" ]] || ! valid_ip "$ip"; then
        printf 'Invalid or empty IP address.\n'
        pause
        return
    fi

    printf '\nUnbanning %s from all active jails:\n' "$ip"
    for jail in $(get_jails); do
        if "$FAIL2BAN_CLIENT" set "$jail" unbanip "$ip" >/dev/null 2>&1; then
            printf '  %-28s OK\n' "$jail"
            result=1
        else
            printf '  %-28s not present\n' "$jail"
        fi
    done

    (( result == 1 )) || printf 'The address was not banned in any active jail.\n'
    pause
}

unban_all() {
    local confirmation jail ip ips total=0

    printf '\nWARNING: This removes every active ban from every Fail2Ban jail.\n'
    read -r -p 'Type UNBAN-ALL to continue: ' confirmation
    if [[ "$confirmation" != "UNBAN-ALL" ]]; then
        printf 'Operation cancelled.\n'
        pause
        return
    fi

    for jail in $(get_jails); do
        ips="$(get_banned_ips "$jail")"
        printf '\nJail: %s\n' "$jail"
        if [[ -z "$ips" ]]; then
            printf '  No banned addresses.\n'
            continue
        fi

        for ip in $ips; do
            if "$FAIL2BAN_CLIENT" set "$jail" unbanip "$ip" >/dev/null 2>&1; then
                printf '  %-39s OK\n' "$ip"
                ((total += 1))
            else
                printf '  %-39s ERROR\n' "$ip"
            fi
        done
    done

    printf '\nCompleted. Removed %d ban record(s).\n' "$total"
    pause
}

menu() {
    local option
    while true; do
        clear
        printf '%s\n' \
            "=======================================" \
            "       FAIL2BAN CONTROL PANEL" \
            "=======================================" \
            "1) List all jails and banned IPs" \
            "2) Unban a specific IP" \
            "3) Unban ALL IPs from ALL jails" \
            "4) Exit" \
            "---------------------------------------"
        read -r -p "Select option: " option

        case "$option" in
            1) list_banned ;;
            2) unban_ip ;;
            3) unban_all ;;
            4) exit 0 ;;
            *) printf 'Invalid option.\n'; sleep 1 ;;
        esac
    done
}

require_root
require_fail2ban
menu
