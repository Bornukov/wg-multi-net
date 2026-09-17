#!/bin/bash
set -euo pipefail

# ============================================================
# Установщик wg-multi-net
# Разворачивает WireGuard-сервер с несколькими изолированными
# сетями, веб-порталом и мониторингом.
# ============================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER_DIR="/opt/wg-manager"
PORTAL_DIR="/opt/wg-portal"

echo "==> Установка wg-multi-net"

# --- 1. Проверка root ---
if [[ $EUID -ne 0 ]]; then
    echo "Запустите скрипт от root: sudo $0"
    exit 1
fi

# --- 2. Проверка .env ---
if [[ ! -f "$REPO_DIR/config/.env" ]]; then
    echo "==> Создайте $REPO_DIR/config/.env на основе .env.example:"
    echo "    cp $REPO_DIR/config/.env.example $REPO_DIR/config/.env"
    echo "    Затем отредактируйте его и запустите скрипт снова."
    exit 1
fi
source "$REPO_DIR/config/.env"

for var in WG_ADMIN_PASSWORD SERVER_IP PORTAL_DOMAIN; do
    val="${!var:-}"
    if [[ -z "$val" || "$val" == CHANGE_ME* ]]; then
        echo "==> Переменная $var не заполнена в config/.env"
        exit 1
    fi
done

# --- 3. Установка пакетов ---
echo "==> Установка пакетов"
apt-get update
apt-get install -y \
    nginx \
    python3 python3-flask python3-gunicorn \
    sqlite3 jq apache2-utils \
    cron \
    ca-certificates curl

# --- 4. Установка Docker (если не установлен) ---
if ! command -v docker &>/dev/null; then
    echo "==> Docker не найден, устанавливаю из официального репозитория"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# --- 5. Копирование файлов ---
echo "==> Копирование файлов"
mkdir -p "$MANAGER_DIR" "$PORTAL_DIR" /usr/local/bin

# /opt/wg-manager
cp "$REPO_DIR/opt/wg-manager/"*.sh "$MANAGER_DIR/"
cp "$REPO_DIR/config/networks.conf" "$MANAGER_DIR/"
cp "$REPO_DIR/config/.env" "$MANAGER_DIR/.env"

# /opt/wg-portal
cp "$REPO_DIR/opt/wg-portal/api.py" "$PORTAL_DIR/"
if [[ -f "$REPO_DIR/opt/wg-portal/names.json" ]]; then
    cp "$REPO_DIR/opt/wg-portal/names.json" "$PORTAL_DIR/"
else
    echo '{"net1":"Сеть 1","net2":"Сеть 2","net3":"Сеть 3","net4":"Сеть 4"}' > "$PORTAL_DIR/names.json"
fi

# /usr/local/bin
cp "$REPO_DIR/usr/local/bin/wg-monitor.sh" /usr/local/bin/
cp "$REPO_DIR/usr/local/bin/update-netangels-cert.sh" /usr/local/bin/

chmod +x "$MANAGER_DIR/"*.sh /usr/local/bin/wg-monitor.sh /usr/local/bin/update-netangels-cert.sh

# --- 6. Права на names.json ---
chown www-data:www-data "$PORTAL_DIR/names.json" 2>/dev/null || true
chmod 664 "$PORTAL_DIR/names.json"

# --- 7. Systemd-сервис ---
echo "==> Настройка systemd-сервиса wg-portal-api"
cp "$REPO_DIR/systemd/wg-portal-api.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now wg-portal-api
systemctl restart wg-portal-api

# --- 8. Nginx ---
echo "==> Настройка Nginx"
# Подставляем реальные значения вместо плейсхолдеров
sed -e "s|__PORTAL_DOMAIN__|${PORTAL_DOMAIN}|g" \
    -e "s|__NET1_DOMAIN__|${NET1_DOMAIN:-net1.${PORTAL_DOMAIN}}|g" \
    -e "s|__NET2_DOMAIN__|${NET2_DOMAIN:-net2.${PORTAL_DOMAIN}}|g" \
    -e "s|__NET3_DOMAIN__|${NET3_DOMAIN:-net3.${PORTAL_DOMAIN}}|g" \
    -e "s|__NET4_DOMAIN__|${NET4_DOMAIN:-net4.${PORTAL_DOMAIN}}|g" \
    -e "s|__SSL_CERT__|${SSL_CERT}|g" \
    -e "s|__SSL_KEY__|${SSL_KEY}|g" \
    "$REPO_DIR/config/nginx-wg-portal.conf" > /etc/nginx/sites-available/wg-portal

ln -sf /etc/nginx/sites-available/wg-portal /etc/nginx/sites-enabled/wg-portal
rm -f /etc/nginx/sites-enabled/default

# htpasswd
if [[ ! -f /etc/nginx/.htpasswd ]]; then
    echo ""
    echo "==> Создайте пароль для Basic Auth (пользователь admin):"
    htpasswd -c /etc/nginx/.htpasswd admin
fi

nginx -t && systemctl reload nginx

# --- 9. Запуск контейнеров ---
echo "==> Запуск контейнеров"
"$MANAGER_DIR/wg-up.sh"

# --- 10. Cron ---
echo "==> Настройка cron"
CRON_TMP=$(mktemp)
crontab -l 2>/dev/null > "$CRON_TMP" || true
grep -q "wg-monitor.sh" "$CRON_TMP" || echo "* * * * * /usr/local/bin/wg-monitor.sh" >> "$CRON_TMP"
grep -q "update-netangels-cert.sh" "$CRON_TMP" || echo "0 3 * * 1 /usr/local/bin/update-netangels-cert.sh >> /var/log/netangels-cert.log 2>&1" >> "$CRON_TMP"
crontab "$CRON_TMP"
rm -f "$CRON_TMP"

# --- 11. Первичная генерация портала ---
/usr/local/bin/wg-monitor.sh

echo ""
echo "============================================================"
echo "Установка завершена!"
echo ""
echo "Портал:       https://${PORTAL_DOMAIN}/"
echo "Админки:      https://${NET1_DOMAIN:-net1.${PORTAL_DOMAIN}}/ ..."
echo "Статус сетей: sudo $MANAGER_DIR/wg-status.sh"
echo ""
echo "Не забудьте:"
echo "  1. Настроить DNS-записи (A) на IP ${SERVER_IP}"
echo "  2. Разместить SSL-сертификат в ${SSL_CERT} и ${SSL_KEY}"
echo "     (или изменить пути в /opt/wg-manager/.env и перезапустить nginx)"
echo "  3. Настроить NetAngels API в /opt/wg-manager/.env для автопродления"
echo "============================================================"
