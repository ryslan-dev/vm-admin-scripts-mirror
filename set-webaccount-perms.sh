#!/bin/bash

# === Параметри ===
ACCOUNT="${1:-}"
BASE="/var/www"

# === Якщо не передано — запитуємо ===
if [[ -z "$ACCOUNT" ]]; then
  read -rp "Введи ім'я акаунта: " ACCOUNT
fi

ACCOUNT_HOME="$BASE/$ACCOUNT"
DATA_DIR="$ACCOUNT_HOME/data"
WWW_DIR="$DATA_DIR/www"
MAIL_DIR="$DATA_DIR/mail"
LOGS_DIR="$DATA_DIR/logs"
BACKUP_DIR="$DATA_DIR/backup"
PHP_BIN_DIR="$DATA_DIR/php-bin"

# === Перевірка існування користувача акаунта ===
if [[ ! $(getent passwd "$ACCOUNT") || ! $(getent group "$ACCOUNT") ]]; then
  echo "❌  Користувач або груа акаунта $ACCOUNT не існує. Перевір ім'я акаунта."
  exit 1
fi

# === Додаємо vmail у групу акаунта ===
if getent passwd vmail > /dev/null; then
    echo "➕ Додаємо vmail у групу $ACCOUNT ..."
    if sudo usermod -aG "$ACCOUNT" vmail; then
      echo "✅  Користувач vmail успішно доданий до групи $ACCOUNT"
    else
      echo "❌  Не вдалося додати vmail до групи $ACCOUNT"
    fi
  else
    echo "⚠️  Користувач vmail не існує — пропущено додавання в групу $ACCOUNT"
fi

# === Перевірка існування папки акаунта ===
if [[ ! -d "$ACCOUNT_HOME" ]]; then
  echo "❌  Директорія $ACCOUNT_HOME не існує. Перевір ім'я акаунта."
  exit 1
fi

echo "🔍  Застосовуємо права до $ACCOUNT ..."

# === Власник і група всього акаунта ===
echo "🔧  Встановлюємо власника $ACCOUNT:$ACCOUNT для $ACCOUNT_HOME ..."
sudo chown -R "$ACCOUNT:$ACCOUNT" "$ACCOUNT_HOME"

# === Основні права на папки акаунта ===
echo "📁  Встановлюємо права 751 на $ACCOUNT_HOME та $DATA_DIR ..."
sudo chmod 751 "$ACCOUNT_HOME"
sudo chmod 751 "$DATA_DIR"
sudo chmod g-s "$ACCOUNT_HOME"
sudo chmod g-s "$DATA_DIR"

# === WWW: сайти ===
if [[ ! -d "$WWW_DIR" ]]; then
  echo "🌐  WWW: Права на директорії 755, файли 644 ..."
  sudo find "$WWW_DIR" -type d -exec chmod 755 {} \;
  sudo find "$WWW_DIR" -type f -exec chmod 644 {} \;
fi

# === LOGS ===
if [[ -d "$LOGS_DIR" ]]; then
  echo "📝  LOGS ..."
  sudo chown -R "$ACCOUNT:$ACCOUNT" "$LOGS_DIR"
  sudo chmod 750 "$LOGS_DIR"
  sudo chmod g-s "$LOGS_DIR"
  sudo find "$LOGS_DIR" -type d -exec chmod 750 {} \;
  sudo find "$LOGS_DIR" -type f -exec chmod 640 {} \;
  sudo setfacl -R -m u:"$ACCOUNT":rwX,g:"$ACCOUNT":rX "$LOGS_DIR"
  sudo setfacl -R -d -m u:"$ACCOUNT":rwX,g:"$ACCOUNT":rX "$LOGS_DIR"
fi

# === BACKUP ===
if [[ -d "$BACKUP_DIR" ]]; then
  echo "🗄️  BACKUP ..."
  sudo chown -R "$ACCOUNT:$ACCOUNT" "$BACKUP_DIR"
  sudo chmod 770 "$BACKUP_DIR"
  sudo chmod g-s "$BACKUP_DIR"
  sudo find "$BACKUP_DIR" -type d -exec chmod 770 {} \;
  sudo find "$BACKUP_DIR" -type f -exec chmod 660 {} \;
  sudo setfacl -R -m u:"$ACCOUNT":rwX,g:"$ACCOUNT":rwX "$BACKUP_DIR"
  sudo setfacl -R -d -m u:"$ACCOUNT":rwX,g:"$ACCOUNT":rwX "$BACKUP_DIR"
fi

# === PHP-BIN ===
if [[ -d "$PHP_BIN_DIR" ]]; then
  echo "🛠️  PHP-BIN ..."
  sudo chown -R "$ACCOUNT:$ACCOUNT" "$PHP_BIN_DIR"
  sudo chmod 770 "$PHP_BIN_DIR"
  sudo chmod g-s "$PHP_BIN_DIR"
  sudo find "$PHP_BIN_DIR" -type d -exec chmod 770 {} \;
  sudo find "$PHP_BIN_DIR" -type f -exec chmod 660 {} \;
  sudo setfacl -R -m u:"$ACCOUNT":rwX,g:"$ACCOUNT":rwX "$PHP_BIN_DIR"
  sudo setfacl -R -d -m u:"$ACCOUNT":rwX,g:"$ACCOUNT":rwX "$PHP_BIN_DIR"
fi

# === MAIL ===
if [[ -d "$MAIL_DIR" ]]; then
  echo "📬  MAIL ..."

  MAIL_USER="$ACCOUNT"

  if getent passwd vmail > /dev/null; then
    MAIL_USER="vmail"
  else
    echo "⚠️  Користувач vmail не існує, тому встановлюємо власника $MAIL_USER:$ACCOUNT"
  fi

  sudo chown -R "$MAIL_USER:$ACCOUNT" "$MAIL_DIR"
  sudo chmod 750 "$MAIL_DIR"
  sudo chmod g-s "$MAIL_DIR"
  sudo find "$MAIL_DIR" -type d -exec chmod 750 {} \;
  sudo find "$MAIL_DIR" -type f -exec chmod 640 {} \;
  sudo setfacl -R -m u:"$MAIL_USER":rwX,g:"$ACCOUNT":rX "$MAIL_DIR"
  sudo setfacl -R -d -m u:"$MAIL_USER":rwX,g:"$ACCOUNT":rX "$MAIL_DIR"
fi

echo "✅  Готово: права та ACL для акаунта $ACCOUNT застосовані."
