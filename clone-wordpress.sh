#!/bin/bash
set -e

# === Парсинг параметрів ===
for arg in "$@"; do
    case $arg in
        account=*) ACCOUNT="${arg#*=}" ;;
        domain=*) DOMAIN="${arg#*=}" ;;
        new_account=*) NEW_ACCOUNT_RAW="${arg#*=}" ;;
        new_domain=*) NEW_DOMAIN="${arg#*=}" ;;
        dbname=*) OPTIONAL_DB_NAME="${arg#*=}" ;;
        dbuser=*) OPTIONAL_DB_USER="${arg#*=}" ;;
        dbpass=*) OPTIONAL_DB_PASS="${arg#*=}" ;;
        site_url=*) SITE_URL="${arg#*=}" ;;
        *)
            echo "❌ Невідомий параметр: $arg"
            exit 1
            ;;
    esac
done

# === Перевірка обов'язкових параметрів ===
if [[ -z "$ACCOUNT" || -z "$DOMAIN" || -z "$NEW_DOMAIN" ]]; then
    echo "❌ Потрібно вказати: account=... domain=... new_domain=..."
    exit 2
fi

NEW_ACCOUNT="$NEW_ACCOUNT_RAW"
[[ -z "$NEW_ACCOUNT_RAW" || "$NEW_ACCOUNT_RAW" == "$ACCOUNT" ]] && NEW_ACCOUNT="$ACCOUNT"

# === Шляхи ===
ACCOUNT_DIR="/var/www/$ACCOUNT"
NEW_ACCOUNT_DIR="/var/www/$NEW_ACCOUNT"
WEB_DIR="$ACCOUNT_DIR/data/www/$DOMAIN"
NEW_WEB_DIR="$NEW_ACCOUNT_DIR/data/www/$NEW_DOMAIN"

# === Перевірка акаунтів ===
for CHECK_ACC in "$ACCOUNT" "$NEW_ACCOUNT"; do
    if [[ ! -d "/var/www/$CHECK_ACC" ]]; then
        echo "❌ Акаунт $CHECK_ACC не існує."
        exit 3
    fi
    if ! id "$CHECK_ACC" &>/dev/null; then
        echo "❌ Системний користувач '$CHECK_ACC' не існує."
        exit 4
    fi
done

# === Перевірка оригінального сайту ===
if [[ ! -d "$WEB_DIR" || ! -f "$WEB_DIR/wp-config.php" ]]; then
    echo "❌ Оригінальний сайт не знайдено: $WEB_DIR"
    exit 5
fi

# === Перевірка нового сайту ===
if [[ ! -d "$NEW_WEB_DIR" ]]; then
    echo "📁 Створюємо папку для нового сайту: $NEW_WEB_DIR"
    mkdir -p "$NEW_WEB_DIR"
else
    if [[ -f "$NEW_WEB_DIR/wp-config.php" ]]; then
        echo "❌ Новий сайт уже встановлений (wp-config.php існує)."
        exit 6
    fi
    echo "🧹 Видаляємо можливі заглушки index.*..."
    rm -f "$NEW_WEB_DIR/index.php" "$NEW_WEB_DIR/index.html" "$NEW_WEB_DIR/index.htm"
fi

# === WP-CLI ===
if ! command -v wp >/dev/null; then
    echo "📦 Встановлюємо wp-cli..."
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
fi

# === Копіюємо файли сайту ===
echo "📁 Копіюємо файли WordPress у $NEW_WEB_DIR..."
rsync -a --exclude='wp-content/cache' "$WEB_DIR/" "$NEW_WEB_DIR/"

# === Витягуємо БД-дані з оригінального сайту ===
DB_NAME_SRC=$(grep DB_NAME "$WEB_DIR/wp-config.php" | cut -d\' -f4)
DB_USER_SRC=$(grep DB_USER "$WEB_DIR/wp-config.php" | cut -d\' -f4)
DB_PASS_SRC=$(grep DB_PASSWORD "$WEB_DIR/wp-config.php" | cut -d\' -f4)

if [[ -z "$DB_NAME_SRC" || -z "$DB_USER_SRC" || -z "$DB_PASS_SRC" ]]; then
    echo "❌ Не вдалося прочитати оригінальні дані БД"
    exit 7
fi

# === Формування імені БД і користувача ===
DOMAIN_SAFE="${NEW_DOMAIN//[^a-zA-Z0-9]/_}"
ACCOUNT_SAFE="${NEW_ACCOUNT//[^a-zA-Z0-9]/_}"
PASS_CHANGED=true

# --- DB_NAME ---
if [[ -n "$OPTIONAL_DB_NAME" ]]; then
    DB_NAME="$OPTIONAL_DB_NAME"
    DB_EXISTS=$(sudo mariadb -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME';")
    if [[ "$DB_EXISTS" -ne 0 ]]; then
        echo "❌ База даних '$DB_NAME' уже існує."
        exit 8
    fi
else
    BASE_DB_NAME="${ACCOUNT_SAFE}_${DOMAIN_SAFE}"
    DB_NAME="$BASE_DB_NAME"
    while sudo mariadb -N -B -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME';" | grep -q "$DB_NAME"; do
        DB_NAME="${BASE_DB_NAME}_$RANDOM"
    done
fi

# --- DB_USER ---
if [[ -n "$OPTIONAL_DB_USER" ]]; then
    DB_USER="$OPTIONAL_DB_USER"
    if [[ -z "$OPTIONAL_DB_PASS" ]]; then
        echo "❌ Ви вказали dbuser=..., але не вказали dbpass=..."
        exit 9
    fi
    DB_PASS="$OPTIONAL_DB_PASS"
    USER_EXISTS=$(sudo mariadb -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE user = '$DB_USER';")
    if [[ "$USER_EXISTS" -eq 0 ]]; then
        echo "👤 Створюємо користувача БД $DB_USER..."
        sudo mariadb -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    else
        echo "ℹ️ Користувач $DB_USER уже існує. Використовуємо його."
        PASS_CHANGED=false
    fi
else
    # Використовуємо того ж користувача та пароль, що і в оригінальному сайті
    DB_USER="$DB_USER_SRC"
    DB_PASS="$DB_PASS_SRC"
    echo "ℹ️ Використовуємо існуючого користувача БД: $DB_USER"
    PASS_CHANGED=false
fi

# === Створення БД ===
echo "🛢️ Створюємо нову базу даних $DB_NAME..."
sudo mariadb -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mariadb -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

# === Тимчасовий дамп та імпорт ===
TMP_DUMP="/tmp/${DB_NAME}_tmp.sql"
echo "📤 Експортуємо дані з оригінальної БД..."
mysqldump -u "$DB_USER_SRC" -p"$DB_PASS_SRC" "$DB_NAME_SRC" > "$TMP_DUMP"
echo "📥 Імпортуємо дамп у нову БД..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$TMP_DUMP"
rm "$TMP_DUMP"

# === Оновлюємо wp-config.php ===
echo "⚙️ Оновлюємо wp-config.php..."
sed -i "s/define( *'DB_NAME'.*/define('DB_NAME', '$DB_NAME');/" "$NEW_WEB_DIR/wp-config.php"
sed -i "s/define( *'DB_USER'.*/define('DB_USER', '$DB_USER');/" "$NEW_WEB_DIR/wp-config.php"
sed -i "s/define( *'DB_PASSWORD'.*/define('DB_PASSWORD', '$DB_PASS');/" "$NEW_WEB_DIR/wp-config.php"

# === Визначаємо стару адресу сайту ===
OLD_URL=$(sudo -u "$ACCOUNT" wp option get home --path="$WEB_DIR")
if [[ -z "$SITE_URL" ]]; then
	if echo | openssl s_client -connect "$NEW_DOMAIN:443" -servername "$NEW_DOMAIN" 2>/dev/null | grep -q "Verify return code: 0 (ok)"; then
		SITE_URL="https://$NEW_DOMAIN"
	else
		SITE_URL="http://$NEW_DOMAIN"
	fi
fi

echo "🌐 Оновлюємо URL у базі даних: $OLD_URL → $SITE_URL"
sudo -u "$NEW_ACCOUNT" wp db query "UPDATE wp_options SET option_value = REPLACE(option_value, '$OLD_URL', '$SITE_URL') WHERE option_name IN ('home', 'siteurl');" --path="$NEW_WEB_DIR"
sudo -u "$NEW_ACCOUNT" wp db query "UPDATE wp_posts SET guid = REPLACE(guid, '$OLD_URL', '$SITE_URL');" --path="$NEW_WEB_DIR"
sudo -u "$NEW_ACCOUNT" wp db query "UPDATE wp_posts SET post_content = REPLACE(post_content, '$OLD_URL', '$SITE_URL');" --path="$NEW_WEB_DIR"

# === Права доступу ===
echo "🔐 Встановлюємо права доступу..."
chown -R "$NEW_ACCOUNT:$NEW_ACCOUNT" "$NEW_WEB_DIR"
find "$NEW_WEB_DIR" -type d -exec chmod 755 {} \;
find "$NEW_WEB_DIR" -type f -exec chmod 644 {} \;

# === Завершено ===
echo
echo "✅ Клон WordPress створено у $NEW_WEB_DIR"
echo "ℹ️  База даних:     $DB_NAME"
echo "ℹ️  Користувач БД:  $DB_USER"
if [[ "$PASS_CHANGED" == true ]]; then
    echo "🔑 Пароль БД:      $DB_PASS"
else
    echo "🔑 Пароль БД:      (не змінено)"
fi
