#!/bin/bash
# init-webpanel.sh
# Ініціалізація webpanel

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

CONFIG_DIR="/etc/webpanel"
CONFIG_FILE="$CONFIG_DIR/mysql-users.conf"

regen=0
login_path="" defaults_file="" socket="" host="" user="" password=""

# Аргументи
for arg in "$@"; do
    case "$arg" in
        -regen) regen=1 ;;
        login-path=*) login_path="${arg#*=}" ;;
        defaults-file=*) defaults_file="${arg#*=}" ;;
        socket=*) socket="${arg#*=}" ;;
        host=*) host="${arg#*=}" ;;
        user=*) user="${arg#*=}" ;;
        password=*) password="${arg#*=}" ;;
        *) log_error "❌ Невідомий аргумент: $arg"; exit 1 ;;
    esac
done

# Генерація паролів
function gen_passwd() {
    openssl rand -base64 20 | tr -dc 'A-Za-z0-9!@#$%^&*()_+=' | head -c 20
}

# Формуємо параметри MySQL
mysql_args=(-N -B --silent)
if [[ -n "$login_path" ]]; then
    mysql_args+=( --login-path="$login_path" )
elif [[ -n "$defaults_file" && -r "$defaults_file" ]]; then
    mysql_args+=( --defaults-file="$defaults_file" )
elif [[ -n "$socket" || -S /var/run/mysqld/mysqld.sock ]]; then
    [[ -z "$socket" ]] && socket=/var/run/mysqld/mysqld.sock
    mysql_args+=( --protocol=socket -S "$socket" -u root )
else
    [[ -n "$host" ]] && mysql_args+=( -h "$host" )
    [[ -n "$user" ]] && mysql_args+=( -u "$user" )
    [[ -n "$password" ]] && mysql_args+=( -p"$password" )
fi

# Якщо файл не існує або --regen → генеруємо нові паролі
if [[ ! -f "$CONFIG_FILE" || $regen -eq 1 ]]; then
    echo "🔢  Генерування паролів для сервісних користувачів..."
	
    ftp_passwd=$(gen_passwd)
	mail_passwd=$(gen_passwd)
    db_passwd=$(gen_passwd)
    admin_passwd=$(gen_passwd)
	
    mkdir -p "$(dirname "$CONFIG_FILE")"
    {
        echo "ftp_passwd=$ftp_passwd"
        echo "mail_passwd=$mail_passwd"
        echo "db_passwd=$db_passwd"
        echo "admin_passwd=$admin_passwd"
    } > "$CONFIG_FILE"
	chmod 700 "$CONFIG_DIR"
    chmod 600 "$CONFIG_FILE"
	
    echo "🔄  Оновлення паролів в MySQL..."
    mysql "${mysql_args[@]}" <<SQL
ALTER USER IF EXISTS 'ftpserver'@'localhost' IDENTIFIED BY '${ftp_passwd}';
ALTER USER IF EXISTS 'mailserver'@'localhost' IDENTIFIED BY '${mail_passwd}';
ALTER USER IF EXISTS 'dbserver'@'localhost' IDENTIFIED BY '${db_passwd}';
ALTER USER IF EXISTS 'webpaneladmin'@'localhost' IDENTIFIED BY '${admin_passwd}';
FLUSH PRIVILEGES;
SQL

    echo "💾  Паролі оновлено і збережено у $CONFIG_FILE"

    echo "🔄  Синхронізація паролів..."
    [[ -x /usr/local/bin/sync-proftpd-passwd.sh ]] && /usr/local/bin/sync-proftpd-passwd.sh
    [[ -x /usr/local/bin/sync-mail-passwd.sh ]] && /usr/local/bin/sync-mail-passwd.sh
    [[ -x /usr/local/bin/sync-db-passwd.sh ]] && /usr/local/bin/sync-db-passwd.sh
else
  # Просто підключає "$CONFIG_FILE" і отримує готові змінні
  source "$CONFIG_FILE"
fi

sql=$(cat <<'SQL'
CREATE DATABASE IF NOT EXISTS webpanel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE webpanel;

-- Таблиця БД
CREATE TABLE IF NOT EXISTS db_list (
  id INT AUTO_INCREMENT PRIMARY KEY,
  db_name VARCHAR(64) NOT NULL UNIQUE,
  uid INT NOT NULL,
  uname VARCHAR(64) NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблиця користувачів БД
CREATE TABLE IF NOT EXISTS db_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  db_user VARCHAR(64) NOT NULL,
  host VARCHAR(64) DEFAULT 'localhost',
  uid INT NOT NULL,
  uname VARCHAR(64) NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY (db_user, host)
);

-- Таблиця доступів БД ↔ користувач
CREATE TABLE IF NOT EXISTS db_access (
  db_id INT NOT NULL,
  db_user_id INT NOT NULL,
  privileges VARCHAR(255) DEFAULT 'ALL PRIVILEGES',
  PRIMARY KEY (db_id, db_user_id),
  FOREIGN KEY (db_id) REFERENCES db_list(id) ON DELETE CASCADE,
  FOREIGN KEY (db_user_id) REFERENCES db_users(id) ON DELETE CASCADE
);

-- FTP-користувачі
CREATE TABLE IF NOT EXISTS ftp_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(255) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  uid INT NOT NULL,
  gid INT NOT NULL,
  homedir VARCHAR(255) NOT NULL,
  shell VARCHAR(255) NOT NULL DEFAULT '/bin/false',
  active TINYINT(1) NOT NULL DEFAULT 1,
  uname VARCHAR(64) NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Групи FTP-користувачів
CREATE TABLE IF NOT EXISTS ftp_groups (
  id INT AUTO_INCREMENT PRIMARY KEY,
  groupname VARCHAR(255) NOT NULL UNIQUE,
  gid INT NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Поштова таблиця
CREATE TABLE IF NOT EXISTS mail_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(128) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  uid INT NOT NULL,
  gid INT NOT NULL,
  homedir VARCHAR(255) NOT NULL,
  uname VARCHAR(64) NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS mail_aliases (
  id INT AUTO_INCREMENT PRIMARY KEY,
  source VARCHAR(128) NOT NULL,
  destination VARCHAR(128) NOT NULL,
  created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY (source, destination)
);
SQL
)

echo "🗃️  Створення бази даних webpanel із службовими таблицями..."
mysql "${mysql_args[@]}" -e "$sql"

echo "🛂  Створення сервісних користувачів та встановлення прав доступу..."

mysql "${mysql_args[@]}" <<SQL
-- FTP-сервер бачить тільки свою таблицю
CREATE USER IF NOT EXISTS 'ftpserver'@'localhost' IDENTIFIED BY '${ftp_passwd}';
GRANT SELECT (username,password,uid,gid,homedir,shell) ON webpanel.ftp_users TO 'ftpserver'@'localhost';
GRANT SELECT ON webpanel.ftp_groups TO 'ftpserver'@'localhost';

-- Пошта бачить лише поштові таблиці
CREATE USER IF NOT EXISTS 'mailserver'@'localhost' IDENTIFIED BY '${mail_passwd}';
GRANT SELECT ON webpanel.mail_users TO 'mailserver'@'localhost';
GRANT SELECT ON webpanel.mail_aliases TO 'mailserver'@'localhost';

-- Скрипти для БД
CREATE USER IF NOT EXISTS 'dbserver'@'localhost' IDENTIFIED BY '${db_passwd}';
GRANT SELECT,INSERT,UPDATE,DELETE ON webpanel.db_list TO 'dbserver'@'localhost';
GRANT SELECT,INSERT,UPDATE,DELETE ON webpanel.db_users TO 'dbserver'@'localhost';
GRANT SELECT,INSERT,UPDATE,DELETE ON webpanel.db_access TO 'dbserver'@'localhost';

-- Адмінка (повні права тільки на webpanel.*)
CREATE USER IF NOT EXISTS 'webpaneladmin'@'localhost' IDENTIFIED BY '${admin_passwd}';
GRANT ALL PRIVILEGES ON webpanel.* TO 'webpaneladmin'@'localhost';

FLUSH PRIVILEGES;
SQL

log_success "Готово! База даних webpanel з усіма таблицями і користувачами створена."
