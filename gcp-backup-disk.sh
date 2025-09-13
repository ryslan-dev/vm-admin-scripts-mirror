#!/bin/bash

# 💽 Створює бекап диска GCP: Snapshot, Image
# Зберігає локально + опційно експортує в GCS + автоочищення

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

# ====== Cleanup ======
cleanup() {
  if [[ -n "${TMP_SNAPSHOT:-}" ]]; then
    warn "🗑️ Видаляю тимчасовий snapshot '$TMP_SNAPSHOT'"
    gcloud compute snapshots delete "$TMP_SNAPSHOT" \
      --project="$PROJECT" --quiet || warn "⚠️ Не вдалося видалити $TMP_SNAPSHOT"
  fi
}
trap cleanup EXIT

# ====== Перевірка залежностей ======
[[ -x "$(command -v gcloud)" ]] || error "❌ Не знайдено gcloud"
[[ -x "$(command -v jq)" ]] || error "❌ Не знайдено jq"

# 📦 Налаштування за замовчуванням
STORAGE_CLASS="ARCHIVE"         # Клас зберігання GCS
LABELS="created-by=gcp-backup-disk,date=$(date +'%Y-%m-%d')"
DATE=$(date +'%Y-%m-%d-%H-%M-%S')
SNAPSHOT=false
IMAGE=false
KEEP_LAST=0
COPY_FLAG=false
MOVE_FLAG=false

# ====== Аргументи ======
for arg in "$@"; do
  case $arg in
    --disk=*) DISK_NAME="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    --snapshot) SNAPSHOT=true ;;
    --snapshot=*) SNAPSHOT_NAME="${arg#*=}"; SNAPSHOT=true ;;
    --image) IMAGE=true ;;
    --image=*) IMAGE_NAME="${arg#*=}"; IMAGE=true ;;
    --copy) COPY_FLAG=true ;;
    --move) MOVE_FLAG=true ;;
    --bucket=*) BUCKET="${arg#*=}" ;;
	--bucket-location=*) BUCKET_LOCATION="${arg#*=}" ;;
    --keep-last=*) KEEP_LAST="${arg#*=}" ;;
    --storage-class=*) STORAGE_CLASS="${arg#*=}" ;;
    --labels=*) LABELS="${arg#*=}" ;;
	--log-file=*) LOG_FILE="${arg#*=}" ;;
    *) error "❌ Невідомий параметр: $arg" ;;
  esac
done

[[ "$SNAPSHOT" == false && "$IMAGE" == false ]] && error "❌ Вкажіть --snapshot чи --image або обидва"
[[ -z "${DISK_NAME:-}" ]] && error "❌ Вкажіть назву диска через --disk=DISK_NAME"

[[ "$COPY_FLAG" == true && "$MOVE_FLAG" == true ]] && error "❌ Вкажіть щось одне з --copy і --move"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

[[ -z "$ZONE" ]] && error "❌ Не вказано зону і не знайдено значення за замовчуванням"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект і не знайдено значення за замовчуванням"

if ! gcloud compute disks describe "$DISK_NAME" --zone="$ZONE" --project="$PROJECT" &>/dev/null; then
  error "❌ Диск '$DISK_NAME' не існує у $ZONE"
fi

[[ "$KEEP_LAST" =~ ^[0-9]+$ ]] || error "❌ --keep-last має бути цілим числом"

BUCKET_LOCATION="${BUCKET_LOCATION:-${ZONE%-*}}"
BUCKET="${BUCKET:-${PROJECT}-${BUCKET_LOCATION}-backups}"

if $COPY_FLAG; then
  EXPORT_MODE="copy"
elif $MOVE_FLAG; then
  EXPORT_MODE="move"
else
  EXPORT_MODE=""
fi

# 📜 Лог-файл
if [[ -n "${LOG_FILE:-}" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

# 📌 Автогенерація імен
[[ "$SNAPSHOT" == true && -z "${SNAPSHOT_NAME:-}" ]] && \
  SNAPSHOT_NAME="${PROJECT}-${ZONE}-${DISK_NAME}-snapshot-${DATE}"
[[ "$IMAGE" == true && -z "${IMAGE_NAME:-}" ]] && \
  IMAGE_NAME="${PROJECT}-${ZONE}-${DISK_NAME}-image-${DATE}"

log "📦 Диск: $DISK_NAME | Зона: $ZONE | Проект: $PROJECT"
$SNAPSHOT && log "📸 Snapshot: $SNAPSHOT_NAME"
$IMAGE && log "🖼 Image: $IMAGE_NAME"
[[ -n "$EXPORT_MODE" ]] && log "☁️ Експорт до GCS ($EXPORT_MODE)"
[[ "$KEEP_LAST" -ge 1 ]] && log "🧹 Залишати останніх: $KEEP_LAST"

# Перевірка чи диск є boot
function is_boot_disk() {
  local DISK_NAME="$1"
  local ZONE="$2"

  for INSTANCE in $(gcloud compute instances list --filter="zone:($ZONE)" --format="value(name)"); do
    gcloud compute instances describe "$INSTANCE" --zone="$ZONE" --format="json" | jq -e \
      --arg disk "zones/$ZONE/disks/$DISK_NAME" \
      '.disks[] | select(.source | endswith($disk)) | select(.boot == true)' >/dev/null && {
        echo "$INSTANCE"
        return 0
      }
  done

  return 1
}

# ===== Функція очищення старих бекапів у GCS =====
function cleanup_old_backups_gcs() {
  local BUCKET_PATH="$1"     # Наприклад: gs://my-backup-bucket/backups
  local NAME_FILTER="$2"     # Наприклад: interkam-europe-west1-b-data-disk-1
  local KEEP_LAST="$3"       # Кількість копій, які треба зберегти

  if [[ -z "$BUCKET_PATH" || -z "$NAME_FILTER" || -z "$KEEP_LAST" ]]; then
    warn "❌ Потрібно вказати BUCKET_PATH, NAME_FILTER і KEEP_LAST для очищення GCS"
    return 1
  fi

  if [[ "$KEEP_LAST" -lt 1 ]]; then
    log "ℹ️ KEEP_LAST < 1 — нічого не видаляємо з $BUCKET_PATH"
    return 0
  fi

  log "🧹 Очищення старих бекапів у $BUCKET_PATH, фільтр: $NAME_FILTER, залишаємо $KEEP_LAST"

  gcloud storage ls --recursive "$BUCKET_PATH" \
    --format="csv[no-heading](name,time_created)" \
    | grep "$NAME_FILTER" \
    | sort -t, -k2 -r \
    | tail -n +$((KEEP_LAST + 1)) \
    | cut -d, -f1 \
    | xargs -r gcloud storage rm --quiet
}


# 📸 Створення Snapshot
if [[ -n "${SNAPSHOT_NAME:-}" ]]; then

  log "📸 Створюю Snapshot: $SNAPSHOT_NAME"
  gcloud compute disks snapshot "$DISK_NAME" \
    --snapshot-names="$SNAPSHOT_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --labels="$LABELS" \
    || error "❌ Не вдалося створити Snapshot"
  log "✅ Snapshot створено"

fi

# 🖼 Створення Image
if [[ -n "${IMAGE_NAME:-}" ]]; then
  
  if is_boot_disk "$DISK_NAME" "$ZONE"; then
    IS_BOOT=true
  else
    IS_BOOT=false
  fi

  if [[ "$IS_BOOT" == false && "$SNAPSHOT" == false ]]; then
    log "📸 Диск $DISK_NAME не є boot. Створюю тимчасовий Snapshot..."
    TMP_SNAPSHOT="${PROJECT}-${ZONE}-${DISK_NAME}-snapshot-${DATE}"
    gcloud compute disks snapshot "$DISK_NAME" \
      --snapshot-names="$TMP_SNAPSHOT" \
      --zone="$ZONE" \
      --project="$PROJECT" \
      --labels="$LABELS" \
      || error "❌ Не вдалося створити тимчасовий Snapshot"
    SNAPSHOT_NAME="$TMP_SNAPSHOT"
  fi

  if [[ "$IS_BOOT" == true ]]; then
    log "🖼 Створюю Image з диска: $IMAGE_NAME"
    gcloud compute images create "$IMAGE_NAME" \
      --source-disk="$DISK_NAME" \
      --source-disk-zone="$ZONE" \
      --project="$PROJECT" \
      --labels="$LABELS" \
      || error "❌ Не вдалося створити Image з диска"
  else
    log "🖼 Створюю Image з Snapshot: $IMAGE_NAME"
    gcloud compute images create "$IMAGE_NAME" \
      --source-snapshot="$SNAPSHOT_NAME" \
      --project="$PROJECT" \
      --labels="$LABELS" \
      || error "❌ Не вдалося створити Image з Snapshot"
  fi

  log "✅ Image створено"
fi

# ☁️ Експорт до GCS
if [[ -n "$EXPORT_MODE" ]]; then

  if ! gsutil ls -b "gs://$BUCKET" &>/dev/null; then
    log "📦 Створюю новий бакет..."
    gsutil mb -p "$PROJECT" -c "$STORAGE_CLASS" -l "$BUCKET_LOCATION" "gs://$BUCKET" || error "❌ Не вдалося створити бакет"
  else
	BUCKET_LOC=$(gsutil ls -L -b "gs://$BUCKET" 2>/dev/null | grep -Ei '^Location constraint:' | awk -F: '{print $2}' | xargs)
    if [[ "$BUCKET_LOC" != "$BUCKET_LOCATION" ]]; then
      warn "⚠️ Bucket '$BUCKET' існує, але має іншу локацію: $BUCKET_LOC"
    fi
  fi

  [[ "$SNAPSHOT" == true ]] && {
    log "☁️ Експорт Snapshot у GCS: $SNAPSHOT_NAME"
    gcloud compute snapshots export "$SNAPSHOT_NAME" \
      --destination-uri="gs://$BUCKET/snapshots/${SNAPSHOT_NAME}.tar.gz" \
      || warn "⚠️ Експорт Snapshot пропущено"
    [[ "$EXPORT_MODE" == "move" ]] && {
      log "🗑 Видаляю Snapshot після експорту: $SNAPSHOT_NAME"
      gcloud compute snapshots delete "$SNAPSHOT_NAME" --quiet
    }
  }
  [[ "$IMAGE" == true ]] && {
    log "☁️ Експорт Image у GCS: $IMAGE_NAME"
    gcloud compute images export "$IMAGE_NAME" \
      --destination-uri="gs://$BUCKET/images/${IMAGE_NAME}.tar.gz" \
      || warn "⚠️ Експорт Image пропущено"
    [[ "$EXPORT_MODE" == "move" ]] && {
      log "🗑 Видаляю Image після експорту: $IMAGE_NAME"
      gcloud compute images delete "$IMAGE_NAME" --quiet
    }
  }
fi

# 🧹 Очищення старих Snapshots
if [[ "$KEEP_LAST" -ge 1 && "$SNAPSHOT" == true ]]; then
  
  log "🧹 Залишаю лише останні $KEEP_LAST Snapshot"
  OLD_SNAPSHOTS=$(gcloud compute snapshots list \
    --filter="name~^${PROJECT}-${ZONE}-${DISK_NAME}-snapshot-" \
    --sort-by=~creationTimestamp \
    --format="value(name)" | tail -n +$((KEEP_LAST + 1)) || true)
  if [[ -n "$OLD_SNAPSHOTS" ]]; then
    log "🔢 Знайдено $(echo "$OLD_SNAPSHOTS" | wc -l) старих Snapshots для видалення"
  fi
  for SNAP in $OLD_SNAPSHOTS; do
    log "🗑 Видаляю старий Snapshot: $SNAP"
    gcloud compute snapshots delete "$SNAP" --quiet || warn "⚠️ Не вдалося видалити $SNAP"
  done
  
  if [[ -n "$EXPORT_MODE" ]]; then
    SNAPSHOTS_BACKUP_PATH="gs://$BUCKET/snapshots"
    NAME_FILTER="${PROJECT}-${ZONE}-${DISK_NAME}-snapshot"
    cleanup_old_backups_gcs "$SNAPSHOTS_BACKUP_PATH" "$NAME_FILTER" "$KEEP_LAST"
  fi
  
else
  log "📦 Очищення для Snapshot вимкнено (KEEP_LAST=$KEEP_LAST)"
fi

# 🧹 Очищення старих Images
if [[ "$KEEP_LAST" -ge 1 && "$IMAGE" == true ]]; then
  
  log "🧹 Залишаю лише останні $KEEP_LAST Image"
  OLD_IMAGES=$(gcloud compute images list \
    --filter="name~^${PROJECT}-${ZONE}-${DISK_NAME}-image-" \
    --sort-by=~creationTimestamp \
    --format="value(name)" | tail -n +$((KEEP_LAST + 1)) || true)
  if [[ -n "$OLD_IMAGES" ]]; then
    log "🔢 Знайдено $(echo "$OLD_IMAGES" | wc -l) старих Images для видалення"
  fi
  for IMG in $OLD_IMAGES; do
    log "🗑 Видаляю старий Image: $IMG"
    gcloud compute images delete "$IMG" --quiet || warn "⚠️ Не вдалося видалити $IMG"
  done
  
  if [[ -n "$EXPORT_MODE" ]]; then
    IMAGES_BACKUP_PATH="gs://$BUCKET/images"
    NAME_FILTER="${PROJECT}-${ZONE}-${DISK_NAME}-image"
    cleanup_old_backups_gcs "$IMAGES_BACKUP_PATH" "$NAME_FILTER" "$KEEP_LAST"
  fi
  
else
  log "📦 Очищення для Image вимкнено (KEEP_LAST=$KEEP_LAST)"
fi

log "✅ Бекап диска завершено успішно!"