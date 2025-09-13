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

log_warn_n() 	  { echo -e "${YELLOW}⚠️ ${NC} $*"; }

# 🛑 Root перевірка
if [[ "$EUID" -ne 0 ]]; then
  log_error "Для роботи скрипта потрібні права root"
  exit 1
fi

user=""
auto_confirm=false
homedir_delete=false

# Перевірка аргументів
for arg in "$@"; do
    case "$arg" in
        -r)
          homedir_delete=true
          ;;
		-y|--yes)
          auto_confirm=true
          ;;
        *)
          user="$arg"
          ;;
    esac
done

if [[ -z "${user:-}" ]]; then
    log_error "Не вказано користувача"
    exit 1
fi

backup_dir="/var/lib/user-locked-shells"
backup_file="$backup_dir/$user.shell"

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

# 🛡 Перевірка критичних користувачів
function is_required_user() {
    [[ "$1" =~ ^(root|nobody|daemon|bin|www-data|vmail|systemd-.*)$ ]]
}

function is_service_user() {
    local user="$1"
    local uid

    # root не є сервісним
    [[ "$user" == "root" ]] && return 1

    # systemd-* вважаємо сервісними
    [[ "$user" =~ ^systemd-.*$ ]] && return 0

    # отримуємо UID
    uid=$(id -u "$user")

    # користувачі з UID від 1 до 999 включно — сервісні
    if [[ "$uid" -gt 0 && "$uid" -lt 1000 ]]; then
        return 0
    fi

    return 1
}

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

# 🛡 Перевірка критичних папок
function is_required_dir() {
    [[ "$1" =~ ^(/|/bin|/dev|/var|/var/backups|/var/mail|/run/sshd|/var/www)$ ]]
}

if ! user_isset "$user"; then
    log_error "Користувача $user не знайдено"
    exit 1
fi

if is_required_user "$user"; then
    log_error "Не можливо видалити користувача $user, бо він є обов'язковим"
    exit 2
fi

# Перевірка активних процесів
if pgrep -u "$user" &>/dev/null; then
    log_error "У користувача $user ще є активні процеси. Спочатку завершіть їх."
    exit 4
fi

if stdout_disabled; then
	auto_confirm=true
fi

# Домашня папка
homedir="$(getent passwd "$user" | cut -d: -f6)"

if [[ "$homedir_delete" == "true" ]] && is_required_dir "$homedir"; then
	log_warn "Папку $homedir не можливо видалити, бо вона є обов'язковою"
	homedir_delete=false
fi

IS_WEBUSER=""
IS_SERVICE_USER=""
if is_webuser "$user"; then
	IS_WEBUSER=1
elif is_service_user "$user"; then
	IS_SERVICE_USER=1
fi

# Підтвердження
if [[ "$auto_confirm" == "false" ]]; then
	if (( IS_WEBUSER )); then
		log_warn_n "Користувач $user є веб-користувачем, ви впевнені що хочете його видалити? "
		read -r -p "[y/N]: " confirm_user
	elif (( IS_SERVICE_USER )); then
		log_warn_n "Користувач $user є сервісним, ви впевнені що хочете його видалити? "
		read -r -p "[y/N]: " confirm_user
	else
		read -p "Ви впевнені що хочете видалити користувача $user? [y/N]: " confirm_user
	fi
    [[ "$confirm_user" =~ ^[Yy]$ ]] || { echo "Видалення користувача $user скасовано"; exit 0; }
	
	if [[ "$homedir_delete" == "true" ]]; then
		if (( IS_WEBUSER || IS_SERVICE_USER )); then
			log_warn_n "Видалити домашню папку $homedir? "
			read -r -p "[y/N]: " confirm_home
		else
			read -p "Видалити домашню папку $homedir? [y/N]: " confirm_home
		fi
		[[ "$confirm_home" =~ ^[Yy]$ ]] || { homedir_delete=false }
	fi
fi

# Видалення користувача
if [[ "$homedir_delete" == "false" ]]; then
	userdel "$user" && {
		echo "👤  Користувача $user видалено"
		echo "📂  Домашню папку $homedir збережено"
	} || {
		log_error "Не вдалося видалити користувача $user"
		exit 3
	}
else
	userdel -r "$user" && {
		echo "👤  Користувача $user видалено"
		echo "📂 → 🗑️  Домашню папку $homedir видалено"
	} || {
		log_error "Не вдалося видалити користувача $user"
		exit 3
	}
fi

# Видалити locked shell backup
if [ -f "$backup_file" ]; then
	rm -f "$backup_file" && echo "🧹  Бекап $backup_file видалено" || log_warn "Не вдалося видалити бекап $backup_file"
fi

if (( IS_WEBUSER )); then
	ftp_users=$(get-ftpuser user="$user" 2>/dev/null | awk '{print $1}' | paste -sd, -)
	if [[ -n ftp_users ]]; then
		if delete-ftpuser "$ftp_users" user="$user" &>/dev/null; then
			echo "🧹  FTP-користувачів видалено"
		else
			log_warn "Не вдалося видалити FTP-користувачів"
		fi
	fi
fi
