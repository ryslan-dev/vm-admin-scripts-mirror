#!/bin/bash

# === Перевірка аргументів ===
if [[ -z "$1" ]]; then
  echo "❌ Помилка: вкажи ім’я акаунта як аргумент."
  echo "   Приклад: $0 interkam [--force]"
  exit 1
fi

user="$1"
user_home="/var/www/$user"
FORCE=0

# === Обробка другого аргументу ===
if [[ "$2" == "--force" ]]; then
  FORCE=1
fi

# === Підтвердження ===
if [[ "$FORCE" -ne 1 ]]; then
  read -rp "⚠️ Увага: буде видалено користувача '$user' і каталог '$user_home'. Продовжити? [y/N] " confirm
  if [[ "$confirm" != [yY] ]]; then
    echo "❌ Скасовано."
    exit 0
  fi
else
  echo "⚙️ Запущено в режимі --force (без підтвердження)"
fi

# === Видалення системного користувача ===
if id "$user" &>/dev/null; then
  echo "👤 Видаляємо користувача $user..."
  sudo userdel -r "$user" 2>/dev/null || {
    echo "⚠️ Користувача видалено, але домашня папка залишилась або була зовнішньою."
  }
else
  echo "ℹ️ Користувача $user не існує або вже видалено."
fi

# === Видалення директорії акаунта ===
if [[ -d "$user_home" ]]; then
  echo "🗑️ Видаляємо каталог $user_home ..."
  sudo rm -rf "$user_home"
else
  echo "ℹ️ Каталог $user_home не існує."
fi

echo "✅ Акаунт $user повністю вилучено."
