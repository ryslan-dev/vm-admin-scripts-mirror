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
unlock_all=true
unlock_passwd=false
unlock_shell=false

# Перевірка аргументів
for arg in "$@"; do
    case "$arg" in
		-p|--passwd)
            unlock_all=false
			unlock_passwd=true
            ;;
		-s|--shell)
            unlock_all=false
			unlock_shell=true
            ;;
        *)
            user="$arg"
            ;;
    esac
done

if [[ "$unlock_passwd" == "true" && "$unlock_shell" == "true" ]]; then
	unlock_all=true
fi

if [[ -z "${user:-}" ]]; then
    log_error "Не вказано користувача"
    exit 1
fi

backup_dir="/var/lib/user-locked-shells"
backup_file="$backup_dir/$user.shell"

# Перевірка існування користувача
function user_isset() {
    id "$1" &>/dev/null
}

# Перевірка блокування користувача
function is_unlocked_user(){
    local user="$1"

    if ! user_passwd_locked "$user" && ! user_shell_locked "$user"; then
        return 0
    else
        return 1
    fi
}

function is_locked_user(){
    local user="$1"

    if user_passwd_locked "$user" && user_shell_locked "$user"; then
        return 0
    else
        return 1
    fi
}

function user_passwd_locked(){
    local user="$1"
	local pass_status
    
	# Перевірка пароля
    pass_status=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')

    if [[ "$pass_status" == "L" || "$pass_status" == "LK" ]]; then
        return 0
    else
        return 1
    fi
}

function user_shell_locked(){
    local user="$1"
	local shell
    
    # Перевірка shell
    shell=$(getent passwd "$user" | cut -d: -f7)
	
    if user_shell_disabled "$user" && [[ -f "$backup_file" ]]; then
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

if ! user_isset "$user"; then
    log_error "Користувача $user не знайдено"
    exit 1
fi

if is_unlocked_user "$user"; then
    log_warn "Користувач не заблокований"
    exit 0
fi

# Розблокування пароля
if [[ "$unlock_all" == "true" || "$unlock_passwd" == "true" ]]; then
	if user_passwd_locked "$user"; then
		usermod -U "$user" && log_success "Пароль користувача $user розблоковано" || {
			log_error "Не вдалося розблокувати пароль користувача $user"
			exit 3
		}
	else
		log_warn "Пароль користувача $user не заблокований"
	fi
fi

# Розблокування shell
if [[ "$unlock_all" == "true" || "$unlock_shell" == "true" ]]; then
	if user_shell_locked "$user"; then

		old_shell=""

		# Прочитати збережений shell
		if [ -f "$backup_file" ]; then
			old_shell=$(cat "$backup_file")
			# Видалити backup
			rm -f "$backup_file"
		fi

		if [[ -n "$old_shell" ]]; then
		usermod -s "$old_shell" "$user" && log_success "Shell-доступ користувача $user розблоковано" || {
			log_error "Не вдалося розблокувати Shell-доступ користувача $user"
			exit 4
		}
		else
			log_error "Не вдалося отримати Shell-доступ, який був до розблокування"
			exit 4
		fi
	else
		log_warn "Shell-доступ користувача $user не заблокований"
	fi
fi

# Висновок
if [[ "$unlock_all" == "true" ]]; then
	if ! is_locked_user "$user"; then
		log_success "Користувача $user розблоковано"
		exit 0
	else
		log_error "Не вдалося повністю розблокувати користувача $user"
		exit 5
	fi
else
  if [[ "$unlock_passwd" == "true" ]]; then
	if ! user_passwd_locked "$user"; then
		log_success "Пароль користувача $user розблоковано"
		exit 0
	else
		log_error "Не вдалося розблокувати пароль користувача $user"
		exit 5
	fi
  fi
  if [[ "$unlock_shell" == "true" ]]; then
    if ! user_shell_locked "$user"; then
		log_success "Shell-доступ користувача $user розблоковано"
		exit 0
	else
		log_error "Не вдалося розблокувати Shell-доступ користувача $user"
		exit 5
	fi
  fi
fi