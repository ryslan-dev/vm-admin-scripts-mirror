#!/bin/bash
# gcp-find-device.sh
# 🔥 Знаходить шлях до підключеного диска у Google Cloud VM

set -euo pipefail
IFS=$'\n\t'

# ===== Кольори =====
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $*"; }
warn()   { echo -e "${YELLOW}[⚠️]${NC} $*"; }
error()  { echo -e "${RED}[✖]${NC} $*" >&2; exit 1; }

# ===== Параметри =====
VM_NAME=""
ZONE=""
PROJECT=""
DISK_NAME=""
VERBOSE=false

for arg in "$@"; do
  case $arg in
    --vm=*) VM_NAME="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    --disk=*) DISK_NAME="${arg#*=}" ;;
    --verbose) VERBOSE=true ;;
    *) error "❌ Невідомий параметр: $arg" ;;
  esac
done

[[ -z "$VM_NAME" ]] && error "❌ Вкажіть VM через --vm"
[[ -z "$DISK_NAME" ]] && error "❌ Вкажіть назву диска через --disk"
ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
[[ -z "$ZONE" ]] && error "❌ Не вказано зону"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект"

$VERBOSE && log "🔍 Шукаємо диск у VM '$VM_NAME' ($ZONE, $PROJECT)"

# ===== Знаходимо всі диски у VM =====
ALL_DEVICES=$(gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="lsblk -dpno NAME,SIZE,MODEL,SERIAL" || true)

if [[ -z "$ALL_DEVICES" ]]; then
  error "❌ Не вдалося отримати список пристроїв у VM '$VM_NAME'"
fi

if $VERBOSE; then
  echo "Всі пристрої у VM:"
  echo "$ALL_DEVICES"
fi

# ===== Фільтруємо диск =====
if [[ -n "$DISK_NAME" ]]; then
  # Фільтруємо конкретний диск
  DEVICE=$(echo "$ALL_DEVICES" | grep "google-${DISK_NAME}" | awk '{print $1}' || true)
else
  DEVICE=""
fi

if [[ -z "$DEVICE" ]]; then
  error "❌ Диск ${DISK_NAME:+($DISK_NAME) }не знайдено у VM '$VM_NAME'"
fi

log "📦 Знайдено диск: $DEVICE"
echo "$DEVICE"
