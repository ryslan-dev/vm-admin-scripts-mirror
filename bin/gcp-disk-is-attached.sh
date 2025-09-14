#!/bin/bash
# gcp-disk-is-attached.sh
# 🔥 Перевіряє чи диск підключений до VM у GCP
# Використовує 2 методи перевірки: швидкий (deviceName) та глибокий (source)

set -euo pipefail
IFS=$'\n\t'

# ===== Кольори для логів =====
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()    { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${GREEN}[✔]${NC} $*"; }
warn()   { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${YELLOW}[⚠️]${NC} $*"; }
error()  { echo -e "${RED}[✖]${NC} $*" >&2; exit 2; }

# ===== Параметри =====
for arg in "$@"; do
  case $arg in
    --vm=*) VM="${arg#*=}" ;;
    --disk=*) DISK="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    --verbose) VERBOSE=true ;;
    *) error "❌ Невідомий параметр: $arg" ;;
  esac
done

[[ -z "${VM:-}" ]] && error "❌ Вкажіть VM через --vm=VM_NAME"
[[ -z "${DISK:-}" ]] && error "❌ Вкажіть диск через --disk=DISK_NAME"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

[[ -z "$ZONE" ]] && error "❌ Не вказано зону і не знайдено значення за замовчуванням"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект і не знайдено значення за замовчуванням"

log "📦 Перевіряємо чи диск '$DISK' підключений до VM '$VM'"

# ===== Метод 1: deviceName =====
if gcloud compute instances describe "$VM" \
  --zone="$ZONE" --project="$PROJECT" \
  --format="value(disks.deviceName)" | grep -q "^$DISK$"; then
  log "✅ Диск '$DISK' знайдено серед deviceName у VM '$VM'"
  exit 0
fi

warn "🔎 Диск '$DISK' не знайдено серед deviceName, пробуємо перевірку source URI"

# ===== Метод 2: source URI =====
if gcloud compute instances describe "$VM" \
  --zone="$ZONE" --project="$PROJECT" \
  --format="flattened(disks[].source)" | grep -q "/disks/$DISK"; then
  log "✅ Диск '$DISK' знайдено у source URI у VM '$VM'"
  exit 0
fi

warn "❌ Диск '$DISK' не підключений до VM '$VM'"
exit 1
