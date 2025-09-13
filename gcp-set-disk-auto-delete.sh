#!/bin/bash
# gcp-set-disk-auto-delete.sh
# Універсальний інструмент для управління auto-delete дисків у VM

set -euo pipefail
IFS=$'\n\t'

# ===== Кольори =====
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[⚠️]${NC} $*"; }
error() { echo -e "${RED}[✖]${NC} $*" >&2; exit 1; }

# ===== Функція usage =====
usage() {
  cat <<EOF
Використання:
  $0 --instance=VM_NAME [--project=PROJECT] [--zone=ZONE]
     [--enable | --disable]
     [--all | --boot | --data | --disk=DISK_NAME]

Параметри:
  --instance=VM_NAME        Ім'я віртуальної машини (обов'язково)
  --project=PROJECT         Проект GCP (опційно)
  --zone=ZONE               Зона GCP (опційно)
  --enable                  Увімкнути auto-delete
  --disable                 Вимкнути auto-delete
  --all                     Змінити для всіх дисків (boot + data)
  --boot                    Змінити тільки для boot-диска
  --data                    Змінити тільки для всіх data-дисків
  --disk=DISK_NAME          Змінити тільки для конкретного диска

Якщо не вказано --enable/--disable — показує всі диски з auto-delete
EOF
  exit 1
}

# ===== Парсинг аргументів =====
INSTANCE=""
PROJECT=""
ZONE=""
ACTION="show"
SCOPE=""
DISK_NAME=""

for arg in "$@"; do
  case $arg in
    --instance=*) INSTANCE="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    --enable) ACTION="enable" ;;
    --disable) ACTION="disable" ;;
    --all) SCOPE="all" ;;
    --boot) SCOPE="boot" ;;
    --data) SCOPE="data" ;;
    --disk=*) SCOPE="disk"; DISK_NAME="${arg#*=}" ;;
    *) usage ;;
  esac
done

# ===== Отримати project і zone якщо не задано =====
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null || echo "")}"
[[ -z "$PROJECT" ]] && error "❌ Не вказано --project і відсутній поточний у gcloud config"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "")}"
[[ -z "$ZONE" ]] && error "❌ Не вказано --zone і відсутня поточна зона у gcloud config"

# ===== Якщо instance не вказано - попросити вибір =====
if [[ -z "$INSTANCE" ]]; then
  log "📦 Отримуємо список VM у проєкті '$PROJECT', зоні '$ZONE'..."
  VM_LIST=$(gcloud compute instances list --project="$PROJECT" --zones="$ZONE" --format="value(name)")
  if [[ -z "$VM_LIST" ]]; then
    error "❌ У зоні '$ZONE' немає доступних VM"
  fi

  echo -e "\nДоступні VM:"
  select vm in $VM_LIST; do
    if [[ -n "$vm" ]]; then
      INSTANCE="$vm"
      break
    else
      echo "⛔ Невірний вибір, спробуйте ще раз."
    fi
  done
fi

log "🔗 Використовуємо VM: $INSTANCE (проект: $PROJECT, зона: $ZONE)"

# ===== Перевірка scope для enable/disable =====
if [[ "$ACTION" != "show" && -z "$SCOPE" ]]; then
  error "❌ Для enable/disable потрібно вказати scope: --all, --boot, --data або --disk=NAME"
fi

# ===== Перевірка gcloud =====
[[ -x "$(command -v gcloud)" ]] || error "❌ Не знайдено gcloud"

# ===== Отримуємо інформацію про диски =====
log "📦 Отримуємо інформацію про диски VM '$INSTANCE'..."
GCLOUD_CMD=(gcloud compute instances describe "$INSTANCE" --format="json" --project="$PROJECT" --zone="$ZONE")

INSTANCE_JSON=$("${GCLOUD_CMD[@]}") || error "❌ Не вдалося отримати інформацію про VM"

DISKS=$(echo "$INSTANCE_JSON" | jq -r '.disks[] | [.deviceName, .boot, .autoDelete] | @tsv')

# ===== Показати всі диски =====
if [[ "$ACTION" == "show" ]]; then
  echo -e "\nДиски VM '$INSTANCE':"
  printf "%-20s %-6s %-12s\n" "DISK NAME" "BOOT" "AUTO_DELETE"
  echo "-------------------------------------------"
  while read -r name boot auto; do
    printf "%-20s %-6s %-12s\n" "$name" "$boot" "$auto"
  done <<< "$DISKS"
  exit 0
fi

# ===== Змінюємо auto-delete =====
set_auto_delete() {
  local disk=$1
  local state=$2
  log "🔄 Змінюємо auto-delete=$state для диска '$disk'..."
  CMD=(gcloud compute instances set-disk-auto-delete "$INSTANCE" --disk="$disk" --"$state" --project="$PROJECT" --zone="$ZONE")
  "${CMD[@]}" || warn "⚠️ Не вдалося змінити auto-delete для диска '$disk'"
}

while read -r name boot auto; do
  case "$SCOPE" in
    all)
      set_auto_delete "$name" "$ACTION"
      ;;
    boot)
      [[ "$boot" == "true" ]] && set_auto_delete "$name" "$ACTION"
      ;;
    data)
      [[ "$boot" == "false" ]] && set_auto_delete "$name" "$ACTION"
      ;;
    disk)
      [[ "$name" == "$DISK_NAME" ]] && set_auto_delete "$name" "$ACTION"
      ;;
  esac
done <<< "$DISKS"

log "✅ Зміни застосовано."
