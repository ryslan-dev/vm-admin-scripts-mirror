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

user=""
passwd=""
np=false
skip=false
allow_shell=false
shell=""
homedir=""

# --- Аргументи ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -np) np=true; shift ;;
		-s) allow_shell=true; shift ;;
		-ns) allow_shell=false; shift ;;
		-skip) skip=true; shift ;;
		passwd=*) passwd="${1#*=}"; shift ;;
		shell=*) shell="${1#*=}"; shift ;;
		home=*) homedir="${1#*=}"; shift ;;
        *)
          if [[ -z "$user" ]]; then
            user="$1"
          else
            log_error "Невідомий аргумент: $1"
            exit 1
          fi
          shift
          ;;
    esac
done

# Перевірка існування користувача
function user_isset() {
    id "$1" &>/dev/null
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

# Оновити пароль
function change_user_passwd(){
	echo "$1:$2" | sudo chpasswd
}

function user_info() {
    local user="$1"

	# --- Отримуємо всю базову інформацію один раз ---
	local user_info groups user_id group_id comment homedir shell
	user_info=$(getent passwd "$user")
	groups=$(id -nG "$user" | sed 's/ /, /g')
	
	IFS=: read -r name _ user_id group_id comment homedir shell <<< "$user_info"

	# --- Основне ---
	echo "Ім’я: $name"
	echo "UID: $user_id"
	echo "GID: $group_id"
	echo "Домашня директорія: $homedir"
	echo "Shell: $shell"
	echo "Групи: $groups"
	if [[ -n "${comment// }" ]]; then
    echo "Коментар: $comment"
	fi
}

if stdout_disabled; then
	if [[ -z "$user" ]]; then
		exit 2
	fi
	if [[ -z "$passwd" && "$np" == "false" ]]; then
		exit 3
	fi
	skip=true
fi

if [[ -z "$user" ]]; then
	read -p "Ім'я нового користувача: " user
fi

if [[ -z "$user" ]]; then
	log_error "Ім'я користувача порожнє"
	exit 2
fi

if user_isset "$user"; then
    log_error "Користувач $user уже існує"
    exit 1
fi

# Команда для створення
cmd=(sudo adduser "$user")

if [[ -n "$passwd" || "$np" == "true" ]]; then
    cmd+=(--disabled-password)
fi

if [[ "$skip" == "true" ]]; then
    cmd+=(--gecos "")
fi

if stdout_disabled; then
cmd+=(-q)
fi

# Створення користувача
"${cmd[@]}" && {
	log_success "Користувача $user додано"
} || {
    log_error "Не вдалося додати користувача $user"
    exit 4
}

# Оновлення пароля
if [[ -n "$passwd" && "$np" == "false" ]]; then
    if ! change_user_passwd "$user" "$passwd"; then
		log_error "Не вдалося задати пароль користувачу $user"
		exit 5
	fi
else
	log_warn "Пароль користувачу $user не задано"
fi

# Зміна Shell
if [[ "$allow_shell" == "false" ]]; then
	shell="/usr/sbin/nologin"
elif [[ -z "$shell" && "$allow_shell" == "true" ]]; then
	shell="/bin/bash"
fi
if [[ -n "$shell" ]]; then
	usermod -s "$shell" "$user"
elif [[ "$skip" == "false" ]]; then
	change-user-shell "$user"
fi

# Зміна папки
if [[ -n "$homedir" ]]; then
	usermod -d "$homedir" -m "$user"
elif [[ "$skip" == "false" ]]; then
	change-user-dir "$user"
fi

# Info
if ! stdout_disabled; then
	user_info "$user"
fi
