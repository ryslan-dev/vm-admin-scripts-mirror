#!/bin/bash
# 
# key="SCRIPT_NAME.sh"
# value="SCRIP_FOLDER/SCRIPT_NAME.sh"
# 
# sudo micro /usr/local/admin-scripts/$value
# sudo chmod +x /usr/local/admin-scripts/$value
# sudo ln -s /usr/local/admin-scripts/$value /usr/local/bin/$key
#
# Підтримує архіви .tar.gz, .tar, .zip, .rar

set -euo pipefail
IFS=$'\n\t'

# 🎨 Функції для кольорових логів
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log_success(){ echo -e "${GREEN}✔ ${NC} $*"; }
log_warn()   { echo -e "${YELLOW}⚠️ ${NC} $*"; }
log_error()  { echo -e "${RED}✖ ${NC} $*" >&2; exit 1; }

confirm() {
  echo -en "${YELLOW}[❓] ${NC} $1 [y/N]: "
  read -r REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

ARCHIVE_PATH=""

# ====== Аргументи ======
for arg in "$@"; do
  case $arg in
    --archive=*) ARCHIVE_PATH="${arg#*=}" ;;
    *)
      echo "Невідомий аргумент: $arg"
      exit 1
      ;;
  esac
done

# 🧩 Асоціативний масив: ["назва_команди"]="відносний/шлях/до_файлу"
declare -A SCRIPTS=(
  # 📦 Бекапи
  ["backup-admin-scripts"]="backup-admin-scripts.sh"
  ["backup-website"]="backup-website.sh"
  ["backup-website-db"]="backup-website-db.sh"
  ["backup-website-files"]="backup-website-files.sh"

  # 🌀 WordPress
  ["clone-wordpress"]="clone-wordpress.sh"
  ["install-wordpress"]="install-wordpress.sh"
  ["delete-wordpress"]="delete-wordpress.sh"
  
  # 🌐 Веб-панель
  ["init-webpanel"]="init-webpanel.sh"
  ["create-webaccount"]="create-webaccount.sh"
  ["delete-webaccount"]="delete-webaccount.sh"
  ["create-website"]="create-website.sh"

  # 📂 FTP
  ["add-ftpuser"]="add-ftpuser.sh"
  ["get-ftpuser"]="get-ftpuser.sh"
  ["update-ftpuser"]="update-ftpuser.sh"
  ["delete-ftpuser"]="delete-ftpuser.sh"

  # 🛠️ Права
  ["set-webaccount-perms"]="set-webaccount-perms.sh"
  ["set-root-perms"]="set-root-perms.sh"
  
  # SSL
  ["issue-website-ssl-certificate"]="issue-website-ssl-certificate.sh"
  ["renew-ssl-certificates"]="renew-ssl-certificates.sh"

  # 🌍 GCP
  ["gcp-backup-disk"]="gcp-backup-disk.sh"
  ["gcp-backup-folder-map"]="gcp-backup-folder-map.sh"
  ["gcp-backup-manager"]="gcp-backup-manager.sh"
  ["gcp-create-disk"]="gcp-create-disk.sh"
  ["gcp-create-instance"]="gcp-create-instance.sh"
  ["gcp-create-template-from-config"]="gcp-create-template-from-config.sh"
  ["gcp-disk-backup-list"]="gcp-disk-backup-list.sh"
  ["gcp-disk-is-attached"]="gcp-disk-is-attached.sh"
  ["gcp-find-disk"]="gcp-find-disk.sh"
  ["gcp-resize-disk-fs"]="gcp-resize-disk-fs.sh"
  ["gcp-restore-config"]="gcp-restore-config.sh"
  ["gcp-restore-disk"]="gcp-restore-disk.sh"
  ["gcp-set-disk-auto-delete"]="gcp-set-disk-auto-delete.sh"

  # ⚙️ Components manager
  ["components-manager"]="components-manager/components-manager.sh"
  ["components-data"]="components-manager/components-data.sh"
  ["component-package"]="components-manager/component-package.sh"
  ["component-service"]="components-manager/component-service.sh"
  ["component-user"]="components-manager/component-user.sh"
  ["component-webuser"]="components-manager/component-webuser.sh"
  ["component-ftpuser"]="components-manager/component-ftpuser.sh"
  ["component-database"]="components-manager/component-database.sh"
  ["component-explorer"]="components-manager/component-explorer.sh"
  ["component-system"]="components-manager/component-system.sh"
  
  # 👥️ Користувачі
  ["get-sudo-users"]="get-sudo-users.sh"
  ["get-sudo-groups"]="get-sudo-groups.sh"
  ["add-user"]="add-user.sh"
  ["add-webuser"]="add-webuser.sh"
  ["delete-user"]="delete-user.sh"
  ["delete-group"]="delete-group.sh"
  ["lock-user"]="lock-user.sh"
  ["unlock-user"]="unlock-user.sh"
  ["change-user-shell"]="change-user-shell.sh"
  ["change-user-dir"]="change-user-dir.sh"
  ["add-user-to-group"]="add-user-to-group.sh"
  ["delete-user-from-group"]="delete-user-from-group.sh"
  ["check-oslogin"]="check-oslogin.sh"
  
  # Провідник
  ["shell-explorer"]="shell-explorer.sh"
  ["shell-explorers"]="shell-explorers.sh"
  ["setup-tmux"]="setup-tmux.sh"
  
  # ⚙️ Інші утиліти
  ["menu-choose"]="menu-choose.sh"
  ["import-db-table"]="import-db-table.sh"
  ["kill-user-vscode-processes"]="kill-user-vscode-processes.sh"
  ["restart-php-pool"]="restart-php-pool.sh"
  ["set-wp-language"]="set-wp-language.sh"
  ["upload-as-root"]="upload-as-root.sh"
  ["vsedit"]="vsedit.sh"
)

ADMIN_SCRIPTS_DIR="/usr/local/admin-scripts/bin"
BIN_DIR="/usr/local/bin"

move_item(){
  local rel="$1"
  local DIR_OLD="$2"
  local DIR_NEW="$3"
  
  # dir
  if [[ "$rel" == */* ]]; then
    local dir="${rel%%/*}"
	local path_old="$DIR_OLD/$dir"
	local path_new="$DIR_NEW/$dir"
	
	if [[ -d "$path_new" ]]; then
		log_success "Папку $dir уже перенесено"
		return 0
	elif [[ -d "$path_old" ]]; then
		mkdir -p "$DIR_NEW"
		mv "$path_old" "$DIR_NEW/"
		log_success "Папку $dir перенесено в $DIR_NEW/"
	else
		log_warn "Папку $path_old не знайдено"
	fi
	
  # file
  else
    local file="$rel"
	local path_old="$DIR_OLD/$rel"
	local path_new="$DIR_NEW/$rel"
	
	if [[ -f "$path_new" ]]; then
		log_success "Файл $file уже перенесено"
		return 0
	elif [[ -f "$path_old" ]]; then
		mkdir -p "$DIR_NEW"
		mv "$path_old" "$path_new"
		log_success "Файл $file перенесено в $DIR_NEW/"
	else
		log_warn "Файл $path_old не знайдено"
	fi
  fi
}

remove_item_link(){
	local key="$1"
	local link_path="$BIN_DIR/$key"
	
	if [[ -L "$link_path" || -e "$link_path" ]]; then
		sudo rm -f "$link_path"
		sudo rm -f "$link_path.sh"
	fi
}

set_item(){
	local key="$1"
	local -n _scripts="$2"
	
	local relative_path="${_scripts[$key]}"
	local full_path="$ADMIN_SCRIPTS_DIR/$relative_path"
	local link_path="$BIN_DIR/$key"
	
	if [[ -f "$full_path" ]]; then
	  
	  remove_item_link "$key"
	
	  sudo chmod +x "$full_path"
      sudo ln -s "$full_path" "$link_path"
	  sed -i 's/\r$//' "$full_path"
	
      log_success "$key встановлено"
	  
	else
	  
	  # Видаляємо залишковий симлінк
      remove_item_link "$key"
	  
	  log_error "Файл $full_path не знайдено"
	fi
}

# 🎯 Функція для розпакування архіву
extract_archive() {
  local archive="$1"
  local dest="$2"

  echo "📦  Розпаковую архів: $archive → $dest"

  case "$archive" in
    *.tar.gz | *.tgz)
      sudo tar -xzf "$archive" -C "$dest"
      ;;
    *.tar)
      sudo tar -xf "$archive" -C "$dest"
      ;;
    *.zip)
      sudo unzip -q "$archive" -d "$dest"
      ;;
    *.rar)
      if ! command -v unrar >/dev/null; then
        log_error "Для розпакування .rar потрібно встановити 'unrar'"
      fi
      sudo unrar x -o+ "$archive" "$dest"
      ;;
    *)
      log_error "Невідомий формат архіву: $archive"
      ;;
  esac
}

# 🧹 Якщо вказано архів — оновлюємо скрипти
if [[ -n "$ARCHIVE_PATH" ]]; then
  echo "ℹ️  Оновлення скриптів з архіву $ARCHIVE_PATH"
  
  if [[ -f "$ARCHIVE_PATH" ]]; then
    sudo mkdir -p "$ADMIN_SCRIPTS_DIR"
	echo "🧹  Видаляю старі файли у $ADMIN_SCRIPTS_DIR"
	
	# 🧹 Очищуємо admin-scripts, крім install-admin-scripts.sh
	for f in "$ADMIN_SCRIPTS_DIR"/*; do
		# Якщо це не сам інсталятор — видаляємо
		if [[ "$(basename "$f")" != "install-admin-scripts.sh" ]]; then
			sudo rm -rf "$f"
		fi
	done
    extract_archive "$ARCHIVE_PATH" "$ADMIN_SCRIPTS_DIR"
  else
    log_error "Архів не знайдено: $ARCHIVE_PATH"
  fi
else
  sudo mkdir -p "$ADMIN_SCRIPTS_DIR"
fi

# Перенесення скриптів у підпапку
#for rel in "${SCRIPTS[@]}"; do
#  move_item "$rel" "/usr/local/admin-scripts" "$ADMIN_SCRIPTS_DIR"
#done

# 🔗 Встановлення симлінків
for key in "${!SCRIPTS[@]}"; do
  set_item "$key" SCRIPTS
done

# Фіксимо знаки переносу рядків
find "$ADMIN_SCRIPTS_DIR" -type f -name "*.sh" -exec sed -i 's/\r$//' {} +

log_success "Встановлення скриптів завершено."
