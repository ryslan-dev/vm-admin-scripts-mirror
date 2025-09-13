#!/bin/bash

# gcp-backup-folder-map.sh
# Створює текстовий файл з картою директорій і файлів для заданого шляху

TARGET_DIR="${1:-/}"
OUTPUT_DIR="/var/backups/folder-maps"
DATE=$(date +'%Y.%m.%d-%H.%M.%S')

# Функції виводу
log()   { echo -e "[\033[1;32m✔\033[0m] $1"; }
warn()  { echo -e "[\033[1;33m⚠️\033[0m] $1"; }
error() { echo -e "[\033[1;31m✖\033[0m] $1" >&2; exit 1; }

# Створюємо директорію для збереження
mkdir -p "$OUTPUT_DIR" || error "Не вдалося створити директорію $OUTPUT_DIR"

if [[ "$TARGET_DIR" == "/" ]]; then
  DIR_NAME="root"
else
  #DIR_NAME=$(basename "$TARGET_DIR")
  DIR_NAME=$(echo "$TARGET_DIR" | sed 's|/|-|g' | sed 's|^-||;s|-$||')
fi

# Визначаємо ім'я файлу
OUTPUT_FILE="$OUTPUT_DIR/${DIR_NAME}-folder-map-$DATE.txt"

log "Створюємо карту папок і файлів для $TARGET_DIR"
log "Збереження у файл: $OUTPUT_FILE"

# Створюємо мапу папок та файлів
cd "$TARGET_DIR" || error "Не вдалося перейти до каталогу $TARGET_DIR"

find . -print > "$OUTPUT_FILE" || error "Помилка при створенні мапи папок"

log "Мапа директорій і файлів створена успішно!"

