#!/bin/bash

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
CYAN='\033[96m'
NC='\033[0m'

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
IFS=',' read -r -a users <<< "${user:-}"

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

# Отримуємо uid і gid системних користувачів
uids=()
for u in "${users[@]}"; do
    uid=$(id -u "$u" 2>/dev/null || true)
    if [[ -n "$uid" ]]; then
        uids+=("$uid")
    fi
done

# Отримуємо uid і gid системного користувача
if [[ -n "${user:-}" && -z "uids" ]]; then
  if is_array_single names; then
    log_error "Системного користувача $user не знайдено"
  else
	log_error "Системних користувачів не знайдено"
  fi
  exit 2
fi

# Перевірка доступності mysql через sudo
if ! sudo mysql -e "SELECT 1;" &>/dev/null; then
    log_error "Не вдалось підключитись до MySQL через sudo. Перевір, чи налаштовано unix_socket для root."
    exit 5
fi

# --- Формуємо SQL-запит ---
where=()

# Додаємо фільтр за іменами
if ! is_array_empty names; then
    # формуємо рядок 'username IN ('name1','name2',...)'
    name_list=$(printf "'%s'," "${names[@]}")
    name_list=${name_list%,}  # прибираємо останню кому
    where+=("username IN ($name_list)")
fi

# Додаємо фільтр пошуку s=, якщо задано
if [[ -n "$search" ]]; then
    where+=("username LIKE '%$search%'")
fi

# Додаємо фільтри за додатковими параметрами, якщо задано
if [[ ${#uids[@]} -gt 0 ]]; then
    uid_list=$(printf "'%s'," "${uids[@]}")
    uid_list=${uid_list%,}
    where+=("uid IN ($uid_list)")
fi

[[ -n "${homedir:-}" ]] && where+=("homedir = '$homedir'")
[[ -n "${shell:-}" ]] && where+=("shell = '$shell'")
[[ -n "${active:-}" ]] && where+=("active = $active")

SQL="SELECT username, uid, gid, homedir, shell, active FROM ftp_users"

if [[ ${#where[@]} -gt 0 ]]; then
    SQL+=" WHERE $(IFS=' AND '; echo "${where[*]}")"
fi

# Виконуємо запит і виводимо результат
result=$(run_mysql "$SQL" | tail -n +2)

# Вивід
if [[ -n "$result" ]]; then
	echo "$result"
else
  if is_array_single names; then
    log_error "Не вдалося отримати FTP-користувача $name"
  else
	log_error "Не вдалося отримати FTP-користувачів"
  fi
  exit 4
fi
