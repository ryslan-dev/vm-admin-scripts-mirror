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
allow_shell=true
shell=""

# --- Аргументи ---
while [[ $# -gt 0 ]]; do
    case "$1" in
		-s) allow_shell=true; shift ;;
		-ns) allow_shell=false; shift ;;
		passwd=*) passwd="${1#*=}"; shift ;;
		shell=*) shell="${1#*=}"; shift ;;
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

# Перевірка існування користувача
function user_isset() {
    id "$1" &>/dev/null
}

# Перевірка існування веб-користувача
function is_webuser() {
    local user="$1"
	
	if ! id "$user" &>/dev/null; then
        return 1
    fi
    
    # Перевірка наявності групи webuser у користувача
    if id -nG "$user" | grep -qw "webusers"; then
        return 0
    fi
	
	return 1
}

function webuser_isset() {
	local user="$1"

	is_webuser "$user"
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
		exit 1
	fi
	if [[ -z "$passwd" ]]; then
		exit 2
	fi
fi

if [[ -z "$user" ]]; then
	read -p "Ім'я нового веб-користувача: " user
fi

if [[ -z "$user" ]]; then
	log_error "Ім'я веб-користувача порожнє"
	exit 1
fi

if [[ -z "$passwd" ]]; then
	read -p "Пароль нового веб-користувача: " passwd
fi

if [[ -z "$passwd" ]]; then
	log_error "Пароль веб-користувача не вказано"
	exit 2
fi

basedir="/var/www/$user"
homedir="$basedir/data"
webdir="$homedir/www"

if [[ "$allow_shell" == "false" ]]; then
	shell="/usr/sbin/nologin"
elif [[ -z "$shell" && "$allow_shell" == "true" ]]; then
	shell="/bin/bash"
fi

# === Створення Групи webusers, якщо не існує ===
getent group webusers || sudo groupadd webusers

if user_isset "$user"; then
    log_warn "Користувач $user уже існує"
	if is_webuser "$user"; then
		log_error "Веб-rористувач $user уже існує"
		exit 3
	else
		# Додавання до групи webusers
		usermod -aG webusers "$user" || {
			log_error "Не вдалося додати до групи webusers"
			exit 4
		}
	fi
else
	# === Створення системного користувача ===
	echo "➕ Створюємо системного користувача $user..."
	sudo useradd -U -m -d "$homedir" -s "$shell" -G webusers "$user"
	echo "$user:$passwd" | sudo chpasswd
	log_success "Cистемного користувача $user створено."	
fi

# === Створення базової структури ===
echo "📁 Створюємо структуру директорій акаунта..."
sudo mkdir -p "$webdir"
for dir in logs mail php-bin backup; do
	sudo mkdir -p "$homedir/$dir"
done
sudo chown -R "$user:$user" "$basedir"

# === Застосування прав до структури акаунта ===
echo "🚀 Застосовуємо права доступу для акаунта..."
sudo set-webaccount-perms "$user"

# === Створення віртуального FTP-користувача ===
echo "🔧 Створюємо віртуального FTP-користувача $user..."
sudo add-ftpuser "$user" passwd="$passwd" user="$user"
log_success "FTP-користувача $user додано."

log_success "Веб-користувача $user створено"

# Info
if ! stdout_disabled; then
	user_info "$user"
fi
