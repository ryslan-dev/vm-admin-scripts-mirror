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
  log_error "Для роботи скрипта потрібні права root"
  exit 1
fi

user="${1:-}"
newdir="${2:-}"

if [[ -z "${user:-}" ]]; then
    log_error "Не вказано користувача"
    exit 1
fi

# Перевірка існування користувача
function user_isset() {
    id "$1" &>/dev/null
}

# 🛡 Перевірка критичних користувачів
function is_required_user() {
    [[ "$1" =~ ^(root|nobody|daemon|bin|www-data|vmail|systemd-.*)$ ]]
}

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

if ! user_isset "$user"; then
    log_error "Користувача $user не знайдено"
    exit 1
fi

if is_required_user "$user"; then
    log_error "Не можливо змінити домашню папку користувача $user, бо він є обов'язковим"
    exit 2
fi

if [[ -z "$newdir" ]] && stdout_disabled; then
	exit 3
fi

if [[ "$newdir" != /* || "$newdir" == "/" ]]; then
    log_error "Невірна директорія: $newdir"
    exit 4
fi

# Поточний shell
current_dir="$(getent passwd "$user" | cut -d: -f6)"
log_info "Поточна домашня директорія користувача $user: $current_dir"

if [[ -z "$newdir" ]]; then
	read -p "Введіть нову: " newdir
fi

if [[ -z "$newdir" ]]; then
	log_error "Порожня назва папки"
	exit 3
fi

# Зміна homedir
usermod -d "$newdir" -m "$user" && log_success "Домашню директорію користувача $user змінено на $newdir" || {
    log_error "Не вдалося змінити домашню директорію користувача $user"
    exit 5
}