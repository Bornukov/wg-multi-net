#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read -rp "Удалить также данные (тома)? [y/N] " ans
REMOVE_VOLUMES=false
[[ "$ans" =~ ^[Yy]$ ]] && REMOVE_VOLUMES=true

while IFS='|' read -r name cidr web_port wg_port; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue

    if docker ps -a --format '{{.Names}}' | grep -q "^wg-${name}$"; then
        echo ">> Останавливаю и удаляю wg-${name}"
        docker stop "wg-${name}" >/dev/null
        docker rm "wg-${name}" >/dev/null

        if $REMOVE_VOLUMES; then
            echo ">> Удаляю том wg-${name}-data"
            docker volume rm "wg-${name}-data" >/dev/null 2>&1 || true
        fi
    fi
done < "$SCRIPT_DIR/networks.conf"

echo ">> Готово."
