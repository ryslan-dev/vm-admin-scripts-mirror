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

group=""
auto_confirm=false

# Перевірка аргументів
for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            auto_confirm=true
            ;;
        *)
            group="$arg"
            ;;
    esac
done

if [[ -z "${group:-}" ]]; then
    log_error "Не вказано назву групи"
    exit 1
fi

# Перевірка існування групи
function group_isset() {
	getent group "$1" >/dev/null
}

# 🛡 Перевірка критичних груп
function group_required() {
    [[ "$1" =~ ^(root|sudo|google-sudoers|adm|www-data|mail|vmail)$ ]]
}

if ! group_isset "$group"; then
    log_error "Групу $group не знайдено"
    exit 1
fi

if group_required "$group"; then
    log_error "Не можливо видалити групу $user, бо вона є обов'язковою"
    exit 2
fi

# Отримуємо GID
gid=$(getent group "$group" | cut -d: -f3)

# Перевірка, чи є група основною для когось
users_with_gid=$(awk -F: -v gid="$gid" '$4 == gid {print $1}' /etc/passwd)

if [[ -n "$users_with_gid" ]]; then
    echo "Група є основною для таких користувачів:"
    echo "$users_with_gid"
    log_warn "Спочатку змініть цим користувачам основну групу (usermod -g newgroup username)."
    exit 1
fi

# Перевірка, чи група є додатковою для когось
users_extra=$(getent group "$group" | cut -d: -f4)
if [[ -n "$users_extra" ]]; then
    echo "Група додатково використовується користувачами: $users_extra"
    log_warn "Вони будуть видалені з групи при її видаленні."
fi

# Підтвердження
if [[ "$auto_confirm" == "false" ]]; then
	read -p "Видалити групу $group? (y/N): " confirm
	[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Видалення скасовано"; exit 0; }
fi

# Видалення групи
if sudo groupdel "$group"; then
    log_success "Групу $group_name видалено"
else
    log_error "Не вдалося видалити групу $group"
    exit 1
fi