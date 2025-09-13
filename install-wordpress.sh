#!/bin/bash
set -e

# === Парсинг параметрів ===
for arg in "$@"; do
    case $arg in
        account=*) ACCOUNT="${arg#*=}" ;;
        domain=*) DOMAIN="${arg#*=}" ;;
        dbname=*) OPTIONAL_DB_NAME="${arg#*=}" ;;
        dbuser=*) OPTIONAL_DB_USER="${arg#*=}" ;;
        dbpass=*) OPTIONAL_DB_PASS="${arg#*=}" ;;
        dbprefix=*) OPTIONAL_DB_PREFIX="${arg#*=}" ;;
        site_url=*) SITE_URL="${arg#*=}" ;;
        site_title=*) site_title="${arg#*=}" ;;
        admin_user=*) admin_user="${arg#*=}" ;;
        admin_pass=*) admin_pass="${arg#*=}" ;;
        admin_email=*) admin_email="${arg#*=}" ;;
        locale=*) locale="${arg#*=}" ;;
        wp_version=*) WP_VERSION="${arg#*=}" ;;
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

# === Перевірка акаунта ===
if [[ ! -d "$ACCOUNT_DIR" ]]; then
    echo "❌ Акаунт $ACCOUNT не існує: $ACCOUNT_DIR"
    exit 3
fi

# === Перевірка системного користувача ===
if ! id "$ACCOUNT" &>/dev/null; then
    echo "❌ Системний користувач '$ACCOUNT' не існує."
    exit 4
fi

# === Перевірка сайту ===
if [[ ! -d "$WEB_DIR" ]]; then
    echo "📁 Створюємо папку для сайту: $WEB_DIR"
    mkdir -p "$WEB_DIR"
else
    if [[ -f "$WEB_DIR/wp-config.php" ]]; then
        echo "❌ Сайт уже встановлений (wp-config.php існує)."
        exit 5
    fi
    echo "🧹 Видаляємо можливі заглушки index.*..."
    rm -f "$WEB_DIR/index.php" "$WEB_DIR/index.html" "$WEB_DIR/index.htm"
fi

cd "$WEB_DIR"

echo "⬇️ Завантаження WordPress..."
if [[ -n "$WP_VERSION" ]]; then
    echo "📦 Завантажуємо WordPress версії $WP_VERSION..."
    WP_ARCHIVE="wordpress-$WP_VERSION.tar.gz"
    wget -q "https://wordpress.org/$WP_ARCHIVE"
else
    echo "📦 Завантажуємо останню версію WordPress..."
    WP_ARCHIVE="latest.tar.gz"
    wget -q "https://wordpress.org/$WP_ARCHIVE"
fi

tar -xzf "$WP_ARCHIVE" --strip-components=1
rm "$WP_ARCHIVE"

# === WP-CLI ===
if ! command -v wp >/dev/null; then
    echo "📦 Встановлюємо wp-cli..."
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp
fi

# === Параметри БД ===
DOMAIN_SAFE="${DOMAIN//[^a-zA-Z0-9]/_}"
ACCOUNT_SAFE="${ACCOUNT//[^a-zA-Z0-9]/_}"
DB_PREFIX="${OPTIONAL_DB_PREFIX:-wp_}"
PASS_CHANGED=true

# --- DB_NAME ---
if [[ -n "$OPTIONAL_DB_NAME" ]]; then
    DB_NAME="$OPTIONAL_DB_NAME"
    DB_EXISTS=$(sudo mariadb -N -B -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME';")
    if [[ "$DB_EXISTS" -ne 0 ]]; then
        echo "❌ База даних '$DB_NAME' уже існує."
        exit 6
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
        exit 7
    fi
    DB_PASS="$OPTIONAL_DB_PASS"
    USER_EXISTS=$(sudo mariadb -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE user = '$DB_USER';")
    if [[ "$USER_EXISTS" -eq 0 ]]; then
        echo "👤 Створюємо користувача БД $DB_USER..."
        sudo mariadb -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    else
        echo "ℹ️ Користувач $DB_USER уже існує, використовуємо його."
        PASS_CHANGED=false
    fi
else
    BASE_DB_USER="${DB_NAME}_user"
    DB_USER="$BASE_DB_USER"
    DB_PASS="$(openssl rand -base64 16)"
    while sudo mariadb -N -B -e "SELECT User FROM mysql.user WHERE User = '$DB_USER';" | grep -q "$DB_USER"; do
        DB_USER="${BASE_DB_USER}_$RANDOM"
    done
    echo "👤 Створюємо нового користувача БД $DB_USER..."
    sudo mariadb -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
fi

# === Створення БД ===
echo "🛢️ Створюємо базу даних $DB_NAME..."
sudo mariadb -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mariadb -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"

# === wp-config.php ===
echo "⚙️ Створюємо wp-config.php..."
sudo -u "$ACCOUNT" wp config create \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --dbhost=localhost \
    --dbprefix="$DB_PREFIX" \
    --path="$WEB_DIR" \
    --skip-check \
    --quiet

# === Формуємо site_url ===
if [[ -z "$SITE_URL" ]]; then
    if echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | grep -q "Verify return code: 0 (ok)"; then
		SITE_URL="https://$DOMAIN"
	else
		SITE_URL="http://$DOMAIN"
	fi
fi

# === Автоматичне встановлення WordPress ===
if [[ -n "$site_title" && -n "$admin_user" && -n "$admin_pass" && -n "$admin_email" ]]; then
    echo "🚀 Виконуємо автоматичне встановлення WordPress..."
    INSTALL_CMD=(
        wp core install
        --url="$SITE_URL"
        --title="$site_title"
        --admin_user="$admin_user"
        --admin_password="$admin_pass"
        --admin_email="$admin_email"
        --path="$WEB_DIR"
        --skip-email
        --quiet
    )
    if [[ -n "$locale" ]]; then
        INSTALL_CMD+=( --locale="$locale" )
    fi

    sudo -u "$ACCOUNT" env HOME="$ACCOUNT_DIR/data" "${INSTALL_CMD[@]}"
    echo "✅ WordPress встановлено автоматично з логіном: $admin_user"

    # --- Пауза, щоб файли точно створились ---
    sleep 2

    # --- Встановлення мови через окремий скрипт ---
    if [[ -n "$locale" ]]; then
        echo "🌍 Встановлюємо мову через set-wp-language..."
        if ! set-wp-language "$ACCOUNT" "$WEB_DIR" "$locale"; then
            echo "⚠️ Не вдалося встановити мову через set-wp-language"
        fi
    fi
else
    echo "ℹ️ Автоматичне встановлення пропущено (не вказано site_title, admin_user, admin_pass, admin_email)"
    echo "➡️ Завершіть встановлення вручну у браузері: $SITE_URL"
fi

# === Права доступу ===
echo "🔐 Встановлюємо права доступу..."
chown -R "$ACCOUNT:$ACCOUNT" "$WEB_DIR"
find "$WEB_DIR" -type d -exec chmod 755 {} \;
find "$WEB_DIR" -type f -exec chmod 644 {} \;

# === Завершено ===
echo
echo "✅ WordPress встановлено у $WEB_DIR"
echo "ℹ️ База даних:     $DB_NAME"
echo "ℹ️ Користувач БД:  $DB_USER"
if [[ "$PASS_CHANGED" == true ]]; then
    echo "🔑 Пароль БД:      $DB_PASS"
else
    echo "🔑 Пароль БД:      (не змінено)"
fi
echo "ℹ️ Префікс таблиць: $DB_PREFIX"
echo "🌐 Перейдіть до $SITE_URL щоб перевірити сайт."
