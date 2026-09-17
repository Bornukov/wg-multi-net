#!/bin/bash
# update-netangels-cert.sh — скачивает свежий SSL-сертификат от NetAngels

set -euo pipefail

# Читаем .env
if [[ -f /opt/wg-manager/.env ]]; then
    source /opt/wg-manager/.env
fi

API_KEY="${NETANGELS_API_KEY:-CHANGE_ME}"
DOMAIN="${NETANGELS_DOMAIN:-CHANGE_ME}"
TARGET_DIR="${NETANGELS_TARGET_DIR:-/etc/nginx/ssl}"

TOKEN_URL="https://panel.netangels.ru/api/gateway/token/"
SEARCH_URL="https://api-ms.netangels.ru/api/v1/certificates/find/"
ARCHIVE_NAME="${DOMAIN//\*/_}.tar"
TEMP_DIR=$(mktemp -d)

for cmd in curl tar jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "Ошибка: $cmd не установлен"
        exit 1
    fi
done

handle_error() {
    echo "API ошибка: $1"
    rm -rf "$TEMP_DIR"
    exit 1
}

echo "Получение токена API..."
token_response=$(curl -s -k -X POST -d "api_key=$API_KEY" "$TOKEN_URL")

if [ $? -ne 0 ]; then
    handle_error "Не удалось подключиться к серверу авторизации"
fi

if echo "$token_response" | jq -e '.error' &> /dev/null; then
    error_msg=$(echo "$token_response" | jq -r '.error')
    handle_error "$error_msg"
fi

TOKEN=$(echo "$token_response" | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    handle_error "Не удалось извлечь токен из ответа"
fi

echo "Поиск сертификата для $DOMAIN..."
search_response=$(curl -s -k -H "Authorization: Bearer ${TOKEN}" "${SEARCH_URL}?domains=${DOMAIN}")

if [ $? -ne 0 ]; then
    handle_error "Ошибка при поиске сертификата"
fi

if echo "$search_response" | jq -e '.error' &> /dev/null; then
    error_msg=$(echo "$search_response" | jq -r '.error')
    handle_error "$error_msg"
fi

cert_id=$(echo "$search_response" | jq -r '.entities[0].id')

if [ -z "$cert_id" ] || [ "$cert_id" == "null" ]; then
    handle_error "Сертификат для $DOMAIN не найден"
fi

echo "Скачивание сертификата ID $cert_id..."
download_url="https://api-ms.netangels.ru/api/v1/certificates/${cert_id}/download/?name=${DOMAIN}&type=tar"

curl -s -k -H "Authorization: Bearer ${TOKEN}" -X GET "$download_url" -o "$TEMP_DIR/$ARCHIVE_NAME"

if [ $? -ne 0 ] || [ ! -f "$TEMP_DIR/$ARCHIVE_NAME" ]; then
    handle_error "Не удалось скачать сертификат"
fi

echo "Обновление сертификата в $TARGET_DIR..."
mkdir -p "$TARGET_DIR"
tar -xf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TARGET_DIR"

if [ $? -ne 0 ]; then
    handle_error "Ошибка распаковки архива"
fi

echo "Перезапуск nginx..."
nginx -t && nginx -s reload

rm -rf "$TEMP_DIR"
echo "Сертификат успешно обновлен!"