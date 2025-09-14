#!/bin/bash

# === Перевірка аргументів ===
if [[ $# -lt 3 ]]; then
  echo "❌ Вкажіть параметри: <файл-джерело> <акаунт> <папка-призначення>"
  echo "Наприклад: logo.png my-account /var/www/my-account/data/www/my-site.com/"
  exit 1
fi

SRC="$1"
ACCOUNT="$2"
DEST_DIR="$3"
DEST_FILE="$DEST_DIR/$(basename "$SRC")"

# === Копіювання з правами та власником ===
echo "📥 Копіюємо $SRC → $DEST_FILE як $ACCOUNT:$ACCOUNT з правами 644"
sudo install -m 644 -o "$ACCOUNT" -g "$ACCOUNT" "$SRC" "$DEST_FILE"

# === Перевірка результату ===
if [[ $? -eq 0 ]]; then
  echo "✅ Успішно скопійовано."
else
  echo "❌ Помилка при копіюванні."
fi
