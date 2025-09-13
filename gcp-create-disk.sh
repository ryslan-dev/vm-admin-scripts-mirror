#!/bin/bash

# 💽 Створює диск GCP з snapshot, image, архіву або gs:// та розширює файлову систему (якщо потрібно)

set -euo pipefail
IFS=$'\n\t'

# 🎨 Функції для кольорових логів
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $*"; }
warn()   { echo -e "${YELLOW}[⚠️]${NC} $*"; }
error()  { echo -e "${RED}[✖]${NC} $*" >&2; exit 1; }
confirm() {
  echo -en "${YELLOW}[❓]${NC} $1 [y/N]: "
  read -r REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

SKIP_FS_RESIZE=false

# ====== Аргументи ======
for arg in "$@"; do
  case $arg in
    --source=*) SOURCE_NAME="${arg#*=}" ;;
    --disk=*) NEW_DISK_NAME="${arg#*=}" ;;
    --type=*) DISK_TYPE="${arg#*=}" ;;
    --size=*) DISK_SIZE="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
	--skip-fs-resize) SKIP_FS_RESIZE=true ;;
    --log-file=*) LOG_FILE="${arg#*=}" ;;
    *) error "❌ Невідомий параметр: $arg" ;;
  esac
done

[[ -z "${SOURCE_NAME:-}" ]] && error "❌ Вкажіть джерело через --source=SNAPSHOT|IMAGE|ARCHIVE|gs://FILE"
[[ -z "${NEW_DISK_NAME:-}" ]] && error "❌ Вкажіть назву диска через --disk=DISK_NAME"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

[[ -z "$ZONE" ]] && error "❌ Не вказано зону і не знайдено значення за замовчуванням"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект і не знайдено значення за замовчуванням"

# 📜 Лог-файл
if [[ -n "${LOG_FILE:-}" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

log "📦 Джерело: $SOURCE_NAME | Диск: $NEW_DISK_NAME | Зона: $ZONE | Проект: $PROJECT"

# ====== Cleanup ======
cleanup() {
  if [[ -n "${TEMP_IMAGE:-}" ]]; then
    warn "🗑️ Видаляємо тимчасовий образ '$TEMP_IMAGE'"
    gcloud compute images delete "$TEMP_IMAGE" --project="$PROJECT" --quiet || true
  fi
  if [[ -n "${TEMP_BUCKET:-}" ]]; then
    if [[ -n "${GCS_FILE:-}" && "$GCS_FILE" == gs://$TEMP_BUCKET/* ]]; then
      warn "🗑️ Видаляємо файл '$GCS_FILE' з бакету"
      gsutil rm "$GCS_FILE" || true
    fi
    warn "🗑️ Видаляємо тимчасовий бакет '$TEMP_BUCKET'"
    gsutil rm -r "gs://$TEMP_BUCKET" || true
  fi
}
trap cleanup EXIT

# ===== Перевіряємо чи диск вже існує =====
if gcloud compute disks list --filter="name=($NEW_DISK_NAME)" --format="value(name)" | grep -q "$NEW_DISK_NAME"; then
  warn "Диск '$NEW_DISK_NAME' вже існує в $ZONE"
  if confirm "Видалити існуючий диск '$NEW_DISK_NAME' і створити новий?"; then
    gcloud compute disks delete "$NEW_DISK_NAME" --zone="$ZONE" --project="$PROJECT" --quiet \
      || error "❌ Не вдалося видалити існуючий диск"
    log "🗑️ Старий диск '$NEW_DISK_NAME' видалено"
  else
    error "⏹️ Створення нового диска перервано користувачем"
  fi
fi

# ===== Нормалізація джерела =====
SOURCE_TYPE=""
TEMP_IMAGE=""
TEMP_BUCKET=""
NORMALIZED_SOURCE=""

if timeout 20 gcloud compute images describe "$SOURCE_NAME" --project="$PROJECT" &>/dev/null; then
  SOURCE_TYPE="gcp-image"
elif timeout 20 gcloud compute snapshots describe "$SOURCE_NAME" --project="$PROJECT" &>/dev/null; then
  SOURCE_TYPE="gcp-snapshot"
elif [[ "$SOURCE_NAME" == *.tar.gz && -f "$SOURCE_NAME" ]]; then
  SOURCE_TYPE="archive"
elif [[ "$SOURCE_NAME" == gs://* ]]; then
  SOURCE_TYPE="gcs-file"
fi

if [[ "$SOURCE_TYPE" == "gcp-snapshot" ]]; then
  log "📸 Джерелом є GCP snapshot"
  NORMALIZED_SOURCE="--source-snapshot=$SOURCE_NAME"

elif [[ "$SOURCE_TYPE" == "gcp-image" ]]; then
  log "📸 Джерелом є GCP image"
  NORMALIZED_SOURCE="--image=$SOURCE_NAME"

elif [[ "$SOURCE_TYPE" == "archive" || "$SOURCE_TYPE" == "gcs-file" ]]; then
  TEMP_IMAGE="tmp-imported-image-$(date +%Y-%m-%d)-$RANDOM"
  if [[ "$SOURCE_TYPE" == "archive" ]]; then
    log "🗜️ Джерелом є архів (.tar.gz)"
    TEMP_BUCKET="tmp-import-bucket-$(date +%Y-%m-%d)-$RANDOM"
    log "🪣 Створюємо тимчасовий бакет: $TEMP_BUCKET"
    gsutil mb -p "$PROJECT" "gs://$TEMP_BUCKET/"
    log "☁️ Завантажуємо $SOURCE_NAME у gs://$TEMP_BUCKET/"
    gsutil cp "$SOURCE_NAME" "gs://$TEMP_BUCKET/"
    GCS_FILE="gs://$TEMP_BUCKET/$(basename "$SOURCE_NAME")"
  else
    log "☁️ Джерелом є файл у Cloud Storage"
    GCS_FILE="$SOURCE_NAME"
  fi
  log "📥 Імпортуємо образ '$TEMP_IMAGE' з $GCS_FILE"
  gcloud compute images import "$TEMP_IMAGE" \
    --source-file="$GCS_FILE" \
    --project="$PROJECT" \
    || error "❌ Не вдалося імпортувати образ"
  NORMALIZED_SOURCE="--image=$TEMP_IMAGE"
else
  error "❌ Невідоме джерело '$SOURCE_NAME'. Підтримується snapshot, image, архів .tar.gz або gs://file"
fi

DISK_TYPE="${DISK_TYPE:-pd-ssd}"
DISK_SIZE="${DISK_SIZE:-10GB}"

# ===== Створення диска =====
log "💽 Створюємо диск '$NEW_DISK_NAME'"
gcloud compute disks create "$NEW_DISK_NAME" \
  $NORMALIZED_SOURCE \
  --zone="$ZONE" \
  --project="$PROJECT" \
  --type="$DISK_TYPE" \
  --size="$DISK_SIZE" \
  --labels="restored-from=$SOURCE_TYPE,date=$(date +'%Y-%m-%d')" \
  || error "❌ Не вдалося створити диск"

log "✅ Диск '$NEW_DISK_NAME' створено успішно"

# 📐 Перевіряємо та розширюємо ФС (якщо потрібно)
if [[ "$SKIP_FS_RESIZE" == false ]]; then
  log "📈 Перевіряємо та розширюємо файлову систему (за потреби)"
  gcp-resize-disk-fs \
    --disk="$NEW_DISK_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    || error "❌ Помилка при перевірці/розширенні файлової системи"
fi