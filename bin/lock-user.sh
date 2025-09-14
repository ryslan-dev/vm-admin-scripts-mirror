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
lock_all=true
lock_passwd=false
lock_shell=false

# Перевірка аргументів
for arg in "$@"; do
    case "$arg" in
		-p|--passwd)
            lock_all=false
			lock_passwd=true
            ;;
		-s|--shell)
            lock_all=false
			lock_shell=true
            ;;
        *)
            user="$arg"
            ;;
    esac
done

if [[ "$lock_passwd" == "true" && "$lock_shell" == "true" ]]; then
	lock_all=true
fi

if [[ -z "${user:-}" ]]; then
    log_error "Не вказано користувача"
    exit 1
fi

backup_dir="/var/lib/user-locked-shells"
backup_file="$backup_dir/$user.shell"

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"

# Перевірка існування користувача
function user_isset() {
    id "$1" &>/dev/null
}

# 🛡 Перевірка критичних користувачів
function is_required_user() {
    [[ "$1" =~ ^(root|nobody|daemon|bin|www-data|vmail|systemd-.*)$ ]]
}

# Перевірка блокування користувача
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

if ! user_isset "$user"; then
    log_error "Користувача $user не знайдено"
    exit 1
fi

if is_required_user "$user"; then
    log_error "Не можливо заблокувати користувача $user, бо він є обов'язковим"
    exit 2
fi

if is_locked_user "$user"; then
    log_warn "Користувач $user уже заблокований"
    exit 0
fi

# Блокування пароля
if [[ "$lock_all" == "true" || "$lock_passwd" == "true" ]]; then
	if ! user_passwd_locked "$user"; then
		usermod -L "$user" && log_success "Пароль користувача $user заблоковано" || {
			log_error "Не вдалося заблокувати пароль користувача $user"
			exit 3
		}
	else
		log_warn "Пароль користувача $user уже заблокований"
	fi
fi

# Блокування Shell
if [[ "$lock_all" == "true" || "$lock_shell" == "true" ]]; then
	if ! user_shell_locked "$user"; then

		# Отримати поточний shell
		current_shell="$(getent passwd "$user" | cut -d: -f7)"

		# Зберегти поточний shell
		if [[ -n "$current_shell" ]]; then
			if ! echo "$current_shell" | tee "$backup_file" >/dev/null; then
				log_warn "Не вдалося зберегти поточний Shell користувача $user"
			fi
		else
			log_warn "Не вдалося отримати поточний shell користувача $user"
		fi

		usermod -s /usr/sbin/nologin "$user" && log_success "Shell-доступ користувача $user заблоковано" || {
			log_error "Не вдалося заблокувати Shell-доступ користувача $user"
			exit 4
		}
	else
		log_warn "Shell-доступ користувача $user уже заблокований"
	fi
fi

# Висновок
if [[ "$lock_all" == "true" ]]; then
  if is_locked_user "$user"; then
    log_success "Користувача $user заблоковано"
    exit 0
  else
	log_error "Не вдалося повністю заблокувати користувача $user"
	exit 5
  fi
else
  if [[ "$lock_passwd" == "true" ]]; then
	if user_passwd_locked "$user"; then
		log_success "Пароль користувача $user заблоковано"
		exit 0
	else
		log_error "Не вдалося заблокувати пароль користувача $user"
		exit 5
	fi
  fi
  if [[ "$lock_shell" == "true" ]]; then
    if user_shell_locked "$user"; then
		log_success "Shell-доступ користувача $user заблоковано"
		exit 0
	else
		log_error "Не вдалося заблокувати Shell-доступ користувача $user"
		exit 5
	fi
  fi
fi
