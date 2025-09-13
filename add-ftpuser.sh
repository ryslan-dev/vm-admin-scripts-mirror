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
  log_error "Дозвіл відхилено"
  exit 1
fi

db_name="webpanel"
name=""
allow_shell=false
shell=""

# --- Аргументи ---
while [[ $# -gt 0 ]]; do
    case "$1" in
		-s) allow_shell=true; shift ;;
		-ns) allow_shell=false; shift ;;
		user=*) user="${1#*=}"; shift ;;
		passwd=*) password="${1#*=}"; shift ;;
		active=*) active="${1#*=}"; shift ;;
		home=*) homedir="${1#*=}"; shift ;;
		shell=*) shell="${1#*=}"; shift ;;
        *)
          if [[ -z "$name" ]]; then
            name="$1"
          else
            log_error "Невідомий аргумент: $1"
            exit 1
          fi
          shift
          ;;
    esac
done

# Перевірка чи загулшений вивід stdout
function stdout_disabled() {

    local target
    target=$(readlink /proc/$$/fd/1 2>/dev/null)

    if [[ "$target" == "/dev/null" ]]; then
        return 0
    else
        return 1
    fi
}

if stdout_disabled; then
	if [[ -z "${name:-}" ]]; then
		exit 1
	fi
	if [[ -z "${password:-}" ]]; then
		exit 2
	fi
	if [[ -z "${user:-}" ]]; then
		exit 3
	fi
fi

if [[ -z "{name:-}" ]]; then
	read -p "Ім'я нового FTP-користувача: " name
fi

if [[ -z "{name:-}" ]]; then
	log_error "Ім'я FTP-користувача порожнє"
	exit 1
fi

if [[ -z "${password:-}" ]]; then
	read -p "Пароль нового FTP-користувача: " password
fi

if [[ -z "{password:-}" ]]; then
	log_error "Пароль FTP-користувача не вказано"
	exit 2
fi

if [[ -z "{user:-}" ]]; then
	read -p "Ім'я системного користувача: " user
fi

if [[ -z "{user:-}" ]]; then
	log_error "Ім'я системного користувача не вказано"
	exit 3
fi

if [[ "$allow_shell" == "false" ]]; then
	shell="/bin/false"
elif [[ -z "$shell" && "$allow_shell" == "true" ]]; then
	shell="/bin/bash"
fi

active="${active:-}"
active="${active,,}"
( [[ "$active" == 1 || "$active" == "true" ]] && active=1 ) || active=0

# Отримуємо uid і gid системного користувача акаунта
user_uid=$(id -u "$user" 2>/dev/null)
user_gid=$(id -g "$user" 2>/dev/null)

if [[ -z "$user_uid" || -z "$user_gid" ]]; then
  log_error "Системного користувача $user не знайдено"
  exit 3
fi

if [[ -z "${homedir:-}" ]]; then
  homedir=$(getent passwd "$user" | cut -d: -f6)
fi

if [[ -z "${homedir:-}" ]]; then
  log_error "Домашньої директорії FTP-користувача $name не визначено"
  exit 4
fi

# Перевірка доступності mysql через sudo
if ! sudo mysql -e "SELECT 1;" &>/dev/null; then
    log_error "Не вдалось підключитись до MySQL через sudo. Перевір, чи налаштовано unix_socket для root."
    exit 7
fi

# Функція для виконання SQL
function run_mysql() {
    local query="$1"
    sudo mysql "$db_name" -e "$query"
}

# Перевірка чи існує вже віртуальний користувач в базі даних
exists=$(run_mysql "SELECT COUNT(*) FROM ftp_users WHERE username = '$name';" | tail -n1)

if [[ "$exists" -gt 0 ]]; then
  log_error "FTP-користувач з іменем $name уже існує"
  exit 5
fi

# Хешуємо пароль SHA-512 crypt
hached_pass=$(openssl passwd -6 "$password")

# SQL-запит для вставки користувача
SQL="INSERT INTO ftp_users (username, password, uid, gid, homedir, shell, active) VALUES ('$name', '$hached_pass', $user_uid, $user_gid, '$homedir', '$shell', $active);"

# Виконуємо SQL-запит
if run_mysql "$SQL"; then
  log_success "FTP-користувача $name додано"
else
  log_error "Не вдалося додати користувача $name."
  exit 6
fi
