#!/bin/bash

set -e

# === Парсинг параметрів ===
for arg in "$@"; do
    case $arg in
        account=*) ACCOUNT="${arg#*=}" ;;
        domain=*) DOMAIN="${arg#*=}" ;;
        *)
            echo "❌ Невідомий параметр: $arg"
            exit 1
            ;;
    esac
done

# === Перевірка обов'язкових параметрів ===
if [[ -z "$ACCOUNT" || -z "$DOMAIN" ]]; then
    echo "❌ Потрібно вказати: account=... domain=..."
    exit 1
fi

ACCOUNT_DIR="/var/www/$ACCOUNT"
WEB_DIR="$ACCOUNT_DIR/data/www/$DOMAIN"

# === Перевірка папки сайту ===
if [[ ! -d "$WEB_DIR" ]]; then
    echo "❌ Папку сайту не знайдено: $WEB_DIR"
    exit 2
fi

# === Витягуємо назву БД з wp-config.php ===
CONFIG_FILE="$WEB_DIR/wp-config.php"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ wp-config.php не знайдено. Не можна визначити базу даних."
    exit 3
fi

DB_NAME=$(grep DB_NAME "$CONFIG_FILE" | cut -d \' -f 4)

if [[ -z "$DB_NAME" ]]; then
    echo "❌ Не вдалося отримати назву БД з wp-config.php"
    exit 4
fi

# === Видаляємо базу даних ===
echo "🧨 Видаляємо базу даних: $DB_NAME..."
sudo mariadb -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"

# === Акуратне видалення типових файлів WP ===
echo "🧹 Акуратно видаляємо типові файли WordPress із $WEB_DIR..."

cd "$WEB_DIR"

rm -rf wp-admin wp-includes wp-content

rm -f \
    index.php \
    xmlrpc.php \
    license.txt \
    readme.html \
    wp-*.php \
    wp-config.php

echo "✅ WordPress акуратно видалено. Інші файли збережені."
