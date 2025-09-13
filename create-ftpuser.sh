#!/bin/bash

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
CYAN='\033[96m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}(i) ${NC} $*" >&2; }
log_success() { echo -e "${GREEN}✔ ${NC} $*" >&2; }
log_warn() 	  { echo -e "${YELLOW}⚠️ ${NC} $*" >&2; }
log_error()   { echo -e "${RED}✖ ${NC} $*" >&2; }

# 🛑 Root перевірка
if [[ "$EUID" -ne 0 ]]; then
  log_error "Потрібні права доступу root"
  exit 1
fi

# Параметри БД
db_name="ftpserver"

# Вхідні обов’язкові параметри
name="${1:-}"
password="${2:-}"
account="${3:-}"

# Опціональні параметри
homedir="${4:-/var/www/$account/data}"
shell="${5:-/bin/false}"
active="${6:-1}"

if [[ -z "$name" || -z "$password" || -z "$account" ]]; then
  log_error "Вкажіть обов'язкові параметри, а також [не обов'язкові] за бажанням: username password account [homedir] [shell] [active]"
  exit 1
fi

# Отримуємо uid і gid системного користувача акаунта
user_uid=$(id -u "$account" 2>/dev/null)
user_gid=$(id -g "$account" 2>/dev/null)

if [[ -z "$user_uid" || -z "$user_gid" ]]; then
  log_error "Користувач акаунта $account не існує. Перевір ім'я акаунта."
  exit 2
fi

# Перевірка доступності mysql через sudo
if ! sudo mysql -e "SELECT 1;" &>/dev/null; then
    log_error "Не вдалось підключитись до MySQL через sudo. Перевір, чи налаштовано unix_socket для root."
    exit 5
fi

# Функція для виконання SQL
function run_mysql() {
    local query="$1"
    sudo mysql "$db_name" -e "$query"
}

# Перевірка чи існує вже віртуальний користувач в базі даних
exists=$(run_mysql "SELECT COUNT(*) FROM ftp_users WHERE username = '$name';" | tail -n1)

if [[ "$exists" -gt 0 ]]; then
  log_error "FTP-користувач з іменем $name уже існує."
  exit 3
fi

# Хешуємо пароль SHA-512 crypt
hashed_pass=$(openssl passwd -6 "$password")

# SQL-запит для вставки користувача
SQL="INSERT INTO ftp_users (username, password, uid, gid, homedir, shell, active) VALUES ('$name', '$hashed_pass', $user_uid, $user_gid, '$homedir', '$shell', $active);"

# Виконуємо SQL-запит
if run_mysql "$SQL"; then
  log_success "FTP-користувач $name доданий успішно."
else
  log_error "Помилка додавання користувача $name."
  exit 4
fi
