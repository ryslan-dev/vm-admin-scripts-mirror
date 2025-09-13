#!/bin/bash

# === Перевірка аргументів ===
if [[ -z "$1" || -z "$2" ]]; then
  echo "❌ Помилка: вкажи ім’я акаунта і пароль як аргументи."
  exit 1
fi

user="$1"
user_pass="$2"
base_dir="/var/www/$user"
data_dir="$base_dir/data"
www_dir="$data_dir/www"
shell="/bin/bash"

# === Створення системного користувача, якщо не існує ===
if id "$user" &>/dev/null; then
  echo "👤 Користувач $user вже існує."
else
  echo "➕ Створюємо системного користувача $user..."
  sudo useradd -m -d "$data_dir" -s "$shell" "$user"
  echo "$user:$user_pass" | sudo chpasswd
  echo "✅ Користувача $user створено."

  # === Створення базової структури ===
  echo "📁 Створюємо структуру директорій акаунта..."
  sudo mkdir -p "$www_dir"
  for dir in logs mail php-bin backup; do
    sudo mkdir -p "$data_dir/$dir"
  done
  sudo chown -R "$user:$user" "$base_dir"
fi

# === Застосування прав до структури акаунта ===
echo "🚀 Застосовуємо права доступу для акаунта..."
sudo set-webuser-perms "$user"

# === Створення віртуального FTP-користувача ===
echo "🔧 Створюємо віртуального FTP-користувача $user..."
sudo add-ftpuser "$user" passwd="$user_pass" user="$user"

echo "✅ Акаунт $user створено та FTP-користувача додано."
