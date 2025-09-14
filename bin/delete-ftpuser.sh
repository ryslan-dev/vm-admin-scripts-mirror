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
user=""
auto_confirm=false

# --- Аргументи ---
while [[ $# -gt 0 ]]; do
    case "$1" in
		-y|--yes)
          auto_confirm=true
          ;;
		user=*) user="${1#*=}"; shift ;;
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

if [[ -z "$name" || -z "$user" ]]; then
  [[ -z "$name" ]] && log_error "Ім'я FTP-користувача порожнє"
  [[ -z "$user" ]] && log_error "Ім'я системного користувача не вказано: user=user_name"
  exit 1
fi

# --- Перетворюємо список імен через кому у масив ---
IFS=',' read -r -a names <<< "$name"

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

function is_array_empty() {
    local -n arr="$1"
    [[ ${#arr[@]} -eq 0 ]]
}

# Перевірка існування користувача
function user_isset() {
    id "$1" &>/dev/null
}

# Функція для виконання SQL
function run_mysql() {
    local query="$1"
    sudo mysql "$db_name" -e "$query"
}

if ! user_isset "$user"; then
  log_error "Системного користувача $user не знайдено"
  exit 2
fi

# Перевірка доступності mysql через sudo
if ! sudo mysql -e "SELECT 1;" &>/dev/null; then
    log_error "Не вдалось підключитись до MySQL через sudo. Перевір, чи налаштовано unix_socket для root."
    exit 5
fi

if stdout_disabled; then
	auto_confirm=true
fi

deleted_users=()
notexists_users=()

# Цикл по всіх FTP-користувачах
for item in "${names[@]}"; do
    item=$(echo "$item" | xargs)  # прибираємо зайві пробіли

    # Перевірка чи існує користувач в базі
    user_EXISTS=$(run_mysql "SELECT COUNT(*) FROM ftp_users WHERE username = '$item';" | tail -n1)
    if [[ "$user_EXISTS" -eq 0 ]]; then
		notexists_users+=("$item")
        log_error "FTP-користувача $item не знайдено"
        continue
    fi
	
	if [[ "$auto_confirm" == "false" ]]; then
		read -p "Ви впевнені що хочете видалити користувача $item? [y/N]: " confirm_item
		[[ "$confirm_item" =~ ^[Yy]$ ]] || { echo "Видалення FTP-користувача $item скасовано"; continue; }
	fi

    # SQL-запит для видалення
    SQL="DELETE FROM ftp_users WHERE username = '$item';"
    if run_mysql "$SQL"; then
        deleted_users+=("$item")
		log_success "FTP-користувача $item видалено"
    else
        log_error "Не вдалося видалити FTP-користувача $item"
    fi
done

if [[ "${#notexists_users[@]}" -eq "${#names[@]}" ]]; then
  exit 3
fi

if is_array_empty deleted_users; then
  exit 4
fi
