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
newshell="${2:-}"
backup_dir="/var/lib/user-locked-shells"
backup_file="$backup_dir/$user.shell"

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

# Перевірка блокування користувача
function user_shell_locked(){
    local user="$1"
	local shell
    
    # Перевірка shell
    shell=$(getent passwd "$user" | cut -d: -f7)
	
    if user_shell_disabled "$user" && [[ -s "$backup_file" ]]; then
		return 0
    fi
	
	return 1
}

function user_shell_disabled(){
    local user="$1"
	local shell
    
    # Перевірка shell
    shell=$(getent passwd "$user" | cut -d: -f7)

    if [[ "$shell" =~ ^(/usr/sbin/nologin|/bin/false)$ ]]; then
        return 0
    else
        return 1
    fi
}

function in_array() {
    local value="$1"
    local -n arr="$2"
    local element
    for element in "${arr[@]}"; do
        [[ "$element" == "$value" ]] && return 0
    done
    return 1
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
    log_error "Не можливо змінити Shell-доступ користувача $user, бо він є обов'язковим"
    exit 2
fi

if user_shell_locked "$user"; then
    log_error "Shell-доступ користувача $user заблокований"
    exit 3
fi

# Поточний shell
current_shell=$(getent passwd "$user" | cut -d: -f7)
log_info "Поточний Shell користувача $user: $current_shell"

# Доступні shells з нумерацією
mapfile -t shells < <(grep -vE '^\s*#' /etc/shells)

if (( ${#shells[@]} == 0 )); then
    log_error "Не знайдено доступних Shells"
    exit 4
fi

if [[ -n "$newshell" ]]; then
	if ! in_array "$newshell" shells; then
		newshell=""
		if stdout_disabled; then
			exit 6
		else
			log_warn "Невірний Shell"
		fi
	fi
fi

if [[ -z "$newshell" ]]; then

	if stdout_disabled; then
		exit 5
	fi
	
	echo "Доступні Shells:"
	
	for i in "${!shells[@]}"; do
		printf "  %d) %s\n" "$((i+1))" "${shells[i]}"
	done
	
	# Вибір нового shell
	read -p "Введіть номер нового Shell для користувача $user: " choice
	if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#shells[@]} )); then
		log_error "Невірний вибір"
		exit 6
	fi
	
	newshell="${shells[$((choice-1))]}"
fi

if [[ -z "$newshell" ]]; then
	log_error "Порожній Shell"
	exit 5
elif ! in_array "$newshell" shells; then
	log_error "Невірний Shell"
	exit 6
fi

# Зміна shell
usermod -s "$newshell" "$user" && log_success "Shell-доступ користувача $user змінено на $newshell" || {
    log_error "Не вдалося змінити Shell-доступ користувача $user"
    exit 7
}