#!/bin/bash

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
CYAN='\033[96m'
NC='\033[0m'

log_success() { echo -e "${GREEN}✔ ${NC} $*" >&2; }
log_error(){ echo -e "${RED}✖ ${NC} $*" >&2; }

# 🛑 Root перевірка
if [[ "$EUID" -ne 0 ]]; then
  log_error "Дозвіл відхилено"
  exit 1
fi

db_name="webpanel"
name=""
search=""

# --- Аргументи ---
while [[ $# -gt 0 ]]; do
    case "$1" in
		s=*) search="${1#*=}"; shift ;;
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

active="${active:-}"
active="${active,,}"
if [[ "${active:-}" == 1 || "${active:-}" == "true" ]]; then
  active=1
elif [[ "${active:-}" == 0 || "${active:-}" == "false" ]]; then
  active=0
fi

# --- Перетворюємо список імен через кому у масив ---
IFS=',' read -r -a names <<< "$name"

function is_array_single() {
    local -n arr="$1"
    [[ "${#arr[@]}" -eq 1 ]]
}

function is_array_empty() {
    local -n arr="$1"
    [[ ${#arr[@]} -eq 0 ]]
}

# Функція для виконання SQL
function run_mysql() {
    local query="$1"
    sudo mysql "$db_name" -e "$query"
}

# Отримуємо uid і gid системного користувача
if [[ -n "${user:-}" ]]; then
	user_uid=$(id -u "$user" 2>/dev/null)
	user_gid=$(id -g "$user" 2>/dev/null)
	
	if [[ -z "$user_uid" || -z "$user_gid" ]]; then
      log_error "Системного користувача $user не знайдено"
      exit 2
	fi	
fi

# Перевірка доступності mysql через sudo
if ! sudo mysql -e "SELECT 1;" &>/dev/null; then
    log_error "Не вдалось підключитись до MySQL через sudo. Перевір, чи налаштовано unix_socket для root."
    exit 5
fi

safe_names=()
for i in "${names[@]}"; do
  safe_name=$(printf "%s" "$i" | sed "s/'/''/g")
  safe_names+=("$safe_name")
done

# --- Формуємо SQL-запит ---
where=()

[[ ${#safe_names[@]} -gt 0 ]] && where+=("username IN ('$(IFS="','"; echo "${safe_names[*]}")')")
[[ -n "{user_uid:-}" ]] && where+=("uid = '$user_uid'")
[[ -n "{search:-}" ]] && where+=("username LIKE '%$search%'")

if [[ ${#where[@]} -eq 0 ]]; then
    log_error "Не вказано фільтр для оновлення"
    exit 3
fi

where_sql=$(IFS=' AND '; echo "${where[*]}")

# --- Формуємо SET для оновлення ---
set=()
[[ -n "{homedir:-}" ]] && set+=("homedir='$homedir'")
[[ -n "{shell:-}" ]] && set+=("shell='$shell'")
[[ -n "{active:-}" ]] && set+=("active='$active'")

if [[ -n "{password:-}" ]]; then
	# Хешуємо пароль SHA-512 crypt
	hached_pass=$(openssl passwd -6 "$password")
	set+=("password='$hached_pass'")
fi

if [[ ${#set[@]} -eq 0 ]]; then
    log_error "Немає полів для оновлення"
    exit 4
fi

set_sql=$(IFS=','; echo "${set[*]}")

# --- Виконуємо UPDATE ---
SQL="UPDATE ftp_users SET $set_sql WHERE $where_sql;"

if run_mysql "$SQL"; then
  if is_array_single names; then
    log_success "FTP-користувача $name оновлено"
  else
	log_success "FTP-користувачів оновлено"
  fi
else
  if is_array_single names; then
    log_error "Не вдалося отримати FTP-користувача $name"
  else
	log_error "Не вдалося отримати FTP-користувачів"
  fi
  exit 4
fi
