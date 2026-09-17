#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

printf "%-8s %-20s %-10s %-10s %-10s\n" "СЕТЬ" "CIDR" "ВЕБ" "WG" "СТАТУС"
printf "%-8s %-20s %-10s %-10s %-10s\n" "-----" "----" "---" "--" "------"

while IFS='|' read -r name cidr web_port wg_port; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue

    if docker ps --format '{{.Names}}' | grep -q "^wg-${name}$"; then
        status="running"
    elif docker ps -a --format '{{.Names}}' | grep -q "^wg-${name}$"; then
        status="stopped"
    else
        status="missing"
    fi

    printf "%-8s %-20s %-10s %-10s %-10s\n" "$name" "$cidr" "$web_port" "$wg_port" "$status"
done < "$SCRIPT_DIR/networks.conf"
