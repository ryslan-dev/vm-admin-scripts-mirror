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

# === Перевірка ===
if [[ -z "$ACCOUNT" || -z "$DOMAIN" ]]; then
    echo "❌ Потрібно вказати: account=... domain=..."
    exit 2
fi

echo "🔁 Бекап сайту $DOMAIN акаунта $ACCOUNT..."

backup-website-db account="$ACCOUNT" domain="$DOMAIN"
backup-website-files account="$ACCOUNT" domain="$DOMAIN"

echo "✅ Успішно завершено."
