#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# 🎨 Функції для кольорових логів
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()    { echo -e "${GREEN}✔${NC} $*"; }
warn()   { echo -e "${YELLOW}⚠️${NC} $*"; }
error()  { echo -e "${RED}✖${NC} $*" >&2; exit 1; }
confirm() {
  echo -en "${YELLOW}[❓]${NC} $1 [y/N]: "
  read -r REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]]
}

# ====== Перевірка залежностей ======
[[ -x "$(command -v gcloud)" ]] || error "Не знайдено gcloud"

# ====== Аргументи ======
for arg in "$@"; do
  case $arg in
    --disk=*) DISK_NAME="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    *) echo "❌ Невідомий параметр: $arg" >&2; exit 1 ;;
  esac
done

[[ -z "${DISK_NAME:-}" ]] && error "Вкажіть назву диска через --disk=DISK_NAME"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

[[ -z "$ZONE" ]] && error "Не вказано зону і не знайдено значення за замовчуванням"
[[ -z "$PROJECT" ]] && error "Не вказано проект і не знайдено значення за замовчуванням"

BUCKET_LOCATION="${ZONE%-*}"
BUCKET="${PROJECT}-${BUCKET_LOCATION}-backups"

echo "📦 Бекапи для диска: $DISK_NAME"
echo "📍 Проект: $PROJECT | Зона: $ZONE | Регіон: $BUCKET_LOCATION"
echo

echo "📸 Snapshots:"
set +e
SNAPSHOT_LIST=$(gcloud compute snapshots list \
  --project="$PROJECT" \
  --filter="name~^${PROJECT}-${ZONE}-${DISK_NAME}-snapshot-" \
  --format="table(name,creationTimestamp.date('%Y-%m-%d %H:%M:%S'),diskSizeGb)" \
  --sort-by=~creationTimestamp)
if [[ -z "$SNAPSHOT_LIST" ]]; then
  echo "  - не знайдено"
else
  echo "$SNAPSHOT_LIST"
fi
set -e

echo
echo "🖼 Images:"
set +e
IMAGE_LIST=$(gcloud compute images list \
  --project="$PROJECT" \
  --filter="name~^${PROJECT}-${ZONE}-${DISK_NAME}-image-" \
  --format="table(name,creationTimestamp.date('%Y-%m-%d %H:%M:%S'),sourceDisk)" \
  --sort-by=~creationTimestamp)
if [[ -z "$IMAGE_LIST" ]]; then
  echo "  - не знайдено"
else
  echo "$IMAGE_LIST"
fi
set -e

echo
echo "☁️ Файли бекапів у бакеті gs://$BUCKET:"

if gsutil ls "gs://$BUCKET/" &>/dev/null; then
  echo "  snapshots:"
  gsutil ls "gs://$BUCKET/snapshots/${PROJECT}-${ZONE}-${DISK_NAME}-snapshot*" 2>/dev/null || echo "    - не знайдено"


  echo "  images:"
  gsutil ls "gs://$BUCKET/images/${PROJECT}-${ZONE}-${DISK_NAME}-image*" 2>/dev/null || echo "    - не знайдено"

else
  warn "  Бакет $BUCKET не існує або недоступний"
fi
