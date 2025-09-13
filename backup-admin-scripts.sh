#!/bin/bash
set -e

# === Шляхи ===
BACKUP_DIR="/var/backups/admin-scripts"
SCRIPTS_DIR="/usr/local/admin-scripts"
DATE=$(date +%Y.%m.%d-%H.%M.%S)
BACKUP_FILE="$BACKUP_DIR/admin-scripts-$DATE.tar.gz"

# === Створюємо папку для бекапів якщо її нема ===
if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "📂 Створюємо папку для бекапів: $BACKUP_DIR"
    sudo mkdir -p "$BACKUP_DIR"
fi

# === Робимо бекап ===
echo "📦 Архівуємо $SCRIPTS_DIR → $BACKUP_FILE"
sudo tar -czf "$BACKUP_FILE" -C "$(dirname "$SCRIPTS_DIR")" "$(basename "$SCRIPTS_DIR")"

# === Завершено ===
echo "✅ Бекап завершено: $BACKUP_FILE"
