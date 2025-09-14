#!/bin/bash
set -e

ACCOUNT="$1"
WEB_DIR="$2"
LOCALE="$3"

if [[ -z "$ACCOUNT" || -z "$WEB_DIR" || -z "$LOCALE" ]]; then
    echo "❌ Використання: ACCOUNT WEB_DIR LOCALE"
    exit 1
fi

ACCOUNT_DIR="/var/www/$ACCOUNT"
HOME_DIR="$ACCOUNT_DIR/data"
WP_CLI_CACHE_DIR="$HOME_DIR/.wp-cli/cache"
LANG_DIR="$WEB_DIR/wp-content/languages"

echo "🌍 Встановлення мови WordPress: $LOCALE"
echo "🔧 Користувач: $ACCOUNT"
echo "📁 Директорія сайту: $WEB_DIR"

# === Кеш WP-CLI ===
if [[ ! -d "$WP_CLI_CACHE_DIR" ]]; then
    echo "📂 Створюємо кеш-папку WP-CLI: $WP_CLI_CACHE_DIR"
    sudo -u "$ACCOUNT" mkdir -p "$WP_CLI_CACHE_DIR"
fi
sudo chown -R "$ACCOUNT:$ACCOUNT" "$HOME_DIR/.wp-cli"
sudo chmod -R 755 "$HOME_DIR/.wp-cli"

# === Папка мов ===
if [[ ! -d "$LANG_DIR" ]]; then
    echo "📂 Створюємо папку для мов: $LANG_DIR"
    mkdir -p "$LANG_DIR"
    sudo chown -R "$ACCOUNT:$ACCOUNT" "$WEB_DIR/wp-content"
    sudo chmod -R 755 "$WEB_DIR/wp-content"
fi

# === Очистка кешу ===
echo "🧹 Очищуємо кеш WP-CLI..."
sudo -u "$ACCOUNT" env HOME="$HOME_DIR" wp cli cache clear --path="$WEB_DIR" --quiet || true

# === Завантаження та активація мови ===
echo "⬇️ Завантажуємо мовний пакет: $LOCALE"
if sudo -u "$ACCOUNT" env HOME="$HOME_DIR" wp language core install "$LOCALE" --path="$WEB_DIR" --quiet; then
    echo "✅ Мову '$LOCALE' встановлено"
    echo "🔄 Активуємо мову: $LOCALE"
    sudo -u "$ACCOUNT" env HOME="$HOME_DIR" wp language core activate "$LOCALE" --path="$WEB_DIR" --quiet
else
    echo "❌ Не вдалося завантажити мовний пакет: $LOCALE"
    exit 2
fi
