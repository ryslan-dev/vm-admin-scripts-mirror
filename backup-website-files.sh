#!/bin/bash
set -e

# === Парсинг параметрів ===
for arg in "$@"; do
    case $arg in
        account=*) ACCOUNT="${arg#*=}" ;;
        domain=*) DOMAIN="${arg#*=}" ;;
        *) echo "❌ Невідомий параметр: $arg"; exit 1 ;;
    esac
done

# === Перевірка параметрів ===
if [[ -z "$ACCOUNT" || -z "$DOMAIN" ]]; then
    echo "❌ Потрібно вказати: account=... domain=..."
    exit 2
fi

ACCOUNT_DIR="/var/www/$ACCOUNT"
WEB_DIR="$ACCOUNT_DIR/data/www/$DOMAIN"
BACKUP_DIR="/var/backups/websites/$ACCOUNT/$DOMAIN"

if [[ ! -d "$WEB_DIR" ]]; then
    echo "❌ Папка сайту не існує: $WEB_DIR"
    exit 3
fi

mkdir -p "$BACKUP_DIR"
DATE=$(date +"%Y.%m.%d-%H.%M.%S")
FILENAME="${DOMAIN}-${DATE}.tar.gz"
FULL_PATH="$BACKUP_DIR/$FILENAME"

echo "📁 Архівуємо файли сайту $WEB_DIR → $FULL_PATH"
tar -czf "$FULL_PATH" -C "$WEB_DIR" .
chown "$ACCOUNT:$ACCOUNT" "$FULL_PATH"
echo "✅ Збережено: $FULL_PATH"
