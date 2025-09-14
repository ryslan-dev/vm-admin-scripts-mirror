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

user=""
group=""
auto_confirm=false

# --- Парсимо аргументи ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            auto_confirm=true
            shift
            ;;
        *)
            if [[ -z "$user" ]]; then
                user="$1"
            elif [[ -z "$group" ]]; then
                group="$1"
            else
                log_error "Невідомий аргумент: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

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

# Перевірка на членство у групі
function user_in_group(){
	id -nG "$1" | grep -qw "$2"
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

if [[ -z "$group" ]] && stdout_disabled; then
	exit 2
fi

if [[ -z "$group" ]]; then
	read -p "Введіть назву групи: " group
fi

if [[ -z "$group" ]]; then
	log_error "Порожня назва групи"
	exit 2
fi

if ! getent group "$group" &>/dev/null; then
    log_error "Групу $group не знайдено"
    exit 3
fi

if user_in_group "$user" "$group"; then
    log_warn "Користувач $user уже є членом групи $group"
	exit 0
fi

if is_required_user "$user" && [[ "$auto_confirm" == "false" ]]; then
    read -rp "Користувач $user є обов'язковим, ви впевнені що хочете додати до групи $group? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Додавання до групи скасовано"; exit 0; }
fi

# Додавання до групи
usermod -aG "$group" "$user" && {
	log_success "Користувача $user додано до групи $group"
	groups=$(id -nG "$user" | sed 's/ /, /g')
	log_info "Групи користувача: $groups"
} || {
    log_error "Не вдалося додати до групи $group"
    exit 4
}
