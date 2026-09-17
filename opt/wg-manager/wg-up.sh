#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

# Генерируем ключ, если не задан
if [[ -z "${WG_WIREGUARD_PRIVATE_KEY:-}" ]]; then
    echo ">> Приватный ключ не задан, генерирую..."
    WG_WIREGUARD_PRIVATE_KEY=$(docker run --rm "$WG_IMAGE" wg genkey)
    # Сохраняем в .env
    sed -i "s|^WG_WIREGUARD_PRIVATE_KEY=.*|WG_WIREGUARD_PRIVATE_KEY=${WG_WIREGUARD_PRIVATE_KEY}|" "$SCRIPT_DIR/.env"
    echo ">> Ключ сохранён в .env"
fi

while IFS='|' read -r name cidr web_port wg_port; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue

    if docker ps -a --format '{{.Names}}' | grep -q "^wg-${name}$"; then
        echo ">> Контейнер wg-${name} уже существует, пропускаю"
        continue
    fi

    echo ">> Запускаю wg-${name} (${cidr}) → веб:${web_port} wg:${wg_port}"

    docker run -d \
        --name "wg-${name}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --device /dev/net/tun:/dev/net/tun \
        --sysctl net.ipv6.conf.all.disable_ipv6=0 \
        --sysctl net.ipv6.conf.all.forwarding=1 \
        -v "wg-${name}-data:/data" \
        -v /lib/modules:/lib/modules:ro \
        -e "WG_ADMIN_PASSWORD=${WG_ADMIN_PASSWORD}" \
        -e "WG_WIREGUARD_PRIVATE_KEY=${WG_WIREGUARD_PRIVATE_KEY}" \
		-e "WG_VPN_CLIENT_ISOLATION=true" \
        -e "WG_VPN_CIDR=${cidr}" \
        -p "${web_port}:8443/tcp" \
        -p "${wg_port}:51820/udp" \
        "$WG_IMAGE"
done < "$SCRIPT_DIR/networks.conf"

echo ">> Готово. Веб-интерфейсы:"
while IFS='|' read -r name cidr web_port wg_port; do
    [[ -z "$name" || "$name" =~ ^# ]] && continue
    echo "   ${name}: https://${SERVER_IP}:${web_port}  (${cidr})"
done < "$SCRIPT_DIR/networks.conf"
