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
    exit 2
fi

ACCOUNT_DIR="/var/www/$ACCOUNT"
WEB_DIR="$ACCOUNT_DIR/data/www/$DOMAIN"
BACKUP_DIR="/var/backups/websites/$ACCOUNT/$DOMAIN"

# === Перевірка сайту ===
if [[ ! -f "$WEB_DIR/wp-config.php" ]]; then
    echo "❌ Не знайдено wp-config.php: $WEB_DIR/wp-config.php"
    exit 3
fi

# === Отримання параметрів БД з wp-config.php ===
DB_NAME=$(grep DB_NAME "$WEB_DIR/wp-config.php" | cut -d \' -f 4)
DB_USER=$(grep DB_USER "$WEB_DIR/wp-config.php" | cut -d \' -f 4)
DB_PASS=$(grep DB_PASSWORD "$WEB_DIR/wp-config.php" | cut -d \' -f 4)

if [[ -z "$DB_NAME" || -z "$DB_USER" || -z "$DB_PASS" ]]; then
    echo "❌ Не вдалося отримати дані БД з wp-config.php"
    exit 4
fi

# === Формуємо назву бекапу ===
DATE=$(date '+%Y.%m.%d-%H.%M.%S')
FILENAME="${DOMAIN}-${DATE}.sql.gz"
FULL_PATH="$BACKUP_DIR/$FILENAME"

# === Створюємо папку для бекапів ===
mkdir -p "$BACKUP_DIR"

# === Бекап бази ===
echo "📦 Створюємо бекап бази даних $DB_NAME → $FULL_PATH"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" | gzip > "$FULL_PATH"

# === Встановлюємо права власника ===
chown "$ACCOUNT:$ACCOUNT" "$FULL_PATH"

echo "✅ Бекап збережено у: $FULL_PATH"
