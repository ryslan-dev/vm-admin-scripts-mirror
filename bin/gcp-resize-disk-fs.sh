#!/bin/bash
# gcp-resize-disk-fs.sh
# Універсальний інструмент для розширення файлової системи на GCP диску
# Працює для всіх сценаріїв: snapshot, image, config, template

set -euo pipefail
IFS=$'\n\t'

# ===== Кольори для логів =====
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

# ====== Аргументи ======
AUTO=true
CREATE_TEMP_VM=false
FS_TYPE="" # ext4 або xfs
FORCE=false
CHECK_ONLY=false
TEMP_ATTACHED=false
NEED_RESIZE=false

for arg in "$@"; do
  case $arg in
    --disk=*) DISK="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    --vm=*) VM_NAME="${arg#*=}" ;;
    --fs=*) FS_TYPE="${arg#*=}" ;;
    --force) FORCE=true ;;
    --check-only) CHECK_ONLY=true ;;
    --log-file=*) LOG_FILE="${arg#*=}" ;;
    *) error "❌ Невідомий параметр: $arg" ;;
  esac
done

[[ -z "${DISK:-}" ]] && error "❌ Вкажіть диск через --disk=DISK_NAME"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"

[[ -z "$ZONE" ]] && error "❌ Не вказано зону і не знайдено значення за замовчуванням"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект і не знайдено значення за замовчуванням"

if [[ -n "${LOG_FILE:-}" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

log "📦 Диск: $DISK | Зона: $ZONE | Проект: $PROJECT"

# ====== Cleanup ======
cleanup() {
  
  if [[ "$TEMP_ATTACHED" == "true" && -n "${TMP_VM:-}" ]]; then
    warn "🔌 Відключаємо тимчасово підключений '$DISK' від VM '$TMP_VM'"
    gcloud compute instances detach-disk "$TMP_VM" --disk="$DISK" --zone="$ZONE" --project="$PROJECT" --quiet || true
  fi

  if [[ "$TEMP_ATTACHED" == "true" && -n "${VM_NAME:-}" ]]; then
    warn "🔌 Відключаємо тимчасово підключений '$DISK' від VM '$VM_NAME'"
    gcloud compute instances detach-disk "$VM_NAME" --disk="$DISK" --zone="$ZONE" --project="$PROJECT" --quiet || true
  fi

  if [[ -n "${TMP_VM:-}" ]]; then
    warn "🗑️ Видаляємо тимчасову VM '$TMP_VM'"
    gcloud compute instances delete "$TMP_VM" --zone="$ZONE" --project="$PROJECT" --quiet || true
  fi
  
}
trap cleanup EXIT

# ===== Перевіряємо чи диск існує =====
gcloud compute disks describe "$DISK" --zone="$ZONE" --project="$PROJECT" >/dev/null \
  || error "❌ Диск '$DISK' не знайдено у $ZONE"

# ===== Отримуємо фізичний розмір диска =====
DISK_SIZE_GB=$(gcloud compute disks describe "$DISK" \
  --zone="$ZONE" --project="$PROJECT" --format="value(sizeGb)")
log "📏 Фізичний розмір диска: ${DISK_SIZE_GB}GB"

# ===== Перевіряємо розмір ФС =====
check_fs_size() {
  local vm="$1"

  # Знаходимо шлях до пристрою
  local device
  device=$(gcp-find-disk.sh --vm="$vm" --disk="$DISK" --zone="$ZONE" --project="$PROJECT") \
  || error "❌ Диск '$DISK' не знайдено у VM '$vm' або не підключений"

  log "🔎 Перевіряємо розмір файлової системи на VM '$vm' (${device})"

  FS_SIZE_GB=$(gcloud compute ssh "$vm" --zone="$ZONE" --project="$PROJECT" --quiet \
    --command="
      if [[ ! -b ${device}1 ]]; then
        echo '0' # Диск не знайдено, вертаємо 0
      else
        sudo lsblk -b -o NAME,SIZE -dn ${device}1 | awk '{print int(\$2/1024/1024/1024)}'
      fi
    " || echo "0")

  if [[ "$FS_SIZE_GB" -eq 0 ]]; then
    warn "⚠️ Не вдалося визначити розмір ФС, припускаємо що потрібен resize"
    return 1
  fi

  log "📏 Розмір файлової системи: ${FS_SIZE_GB}GB"

  if (( FS_SIZE_GB == DISK_SIZE_GB )); then
    log "✅ Файлова система вже займає весь об'єм диска"
    return 0
  else
    warn "⚠️ Файлова система менша на $((DISK_SIZE_GB - FS_SIZE_GB))GB"
    return 1
  fi
}


# ===== Визначаємо VM для перевірки =====
if [[ -n "${VM_NAME:-}" ]]; then

  if gcp-disk-is-attached --vm="$VM_NAME" --disk="$DISK" --zone="$ZONE" --project="$PROJECT"; then
    
	log "✅ Диск '$DISK' вже підключений до VM '$VM_NAME'"
	
  else
    
	log "🔌 Тимчасово підключаємо диск '$DISK' до VM '$VM_NAME'"
    
	gcloud compute instances attach-disk "$VM_NAME" --disk="$DISK" \
      --device-name=resize-disk --zone="$ZONE" --project="$PROJECT"
	
	TEMP_ATTACHED=true
  fi

  check_fs_size "$VM_NAME" || NEED_RESIZE=true

else

  TMP_VM="tmp-resize-vm-$(date +%s)"
  
  log "🖥️ Створюємо тимчасову VM '$TMP_VM'"
  
  gcloud compute instances create "$TMP_VM" \
    --machine-type=e2-micro --zone="$ZONE" --project="$PROJECT" \
    --image-family=debian-11 --image-project=debian-cloud \
    --labels="temporary-resize=true,date=$(date +'%Y-%m-%d')" --quiet \
    || error "❌ Не вдалося створити тимчасову VM"
	
  log "🔌 Тимчасово підключаємо диск '$DISK' до тимчасової VM '$TMP_VM'"

  gcloud compute instances attach-disk "$TMP_VM" --disk="$DISK" \
    --device-name=resize-disk --zone="$ZONE" --project="$PROJECT"
	
  TEMP_ATTACHED=true

  check_fs_size "$TMP_VM" || NEED_RESIZE=true
fi

if $CHECK_ONLY; then
  log "🔍 Перевірку завершено"
  if [[ "$NEED_RESIZE" == "true" ]]; then
    log "✅ Розширення потрібне"
  else
    log "✅ Розширення не потрібне"
  fi
  exit 0
fi

if [[ "$NEED_RESIZE" != "true" && "$FORCE" != "true" ]]; then
  log "✅ Розширення не потрібне"
  exit 0
fi

# ===== Розширюємо ФС =====
resize_in_vm() {
  local vm="$1"

  # Знаходимо шлях до пристрою
  local device
  device=$(gcp-find-disk.sh --vm="$vm" --disk="$DISK" --zone="$ZONE" --project="$PROJECT") \
  || error "❌ Диск '$DISK' не знайдено у VM '$vm' або не підключений"

  log "📈 Виконуємо growpart і resize на VM '$vm' (${device})"

  gcloud compute ssh "$vm" --zone="$ZONE" --project="$PROJECT" --quiet --tunnel-through-iap \
    --command="
      if [[ ! -b ${device}1 ]]; then
        echo '❌ Блочний пристрій ${device}1 не знайдено'; exit 1
      fi
      sudo apt-get update -y && sudo apt-get install -y cloud-guest-utils gdisk xfsprogs || true
      sudo growpart ${device} 1
      FS_TYPE=\$(sudo blkid -o value -s TYPE ${device}1 || echo ext4)
      case \"\$FS_TYPE\" in
        ext4) sudo resize2fs ${device}1 ;;
        xfs) sudo xfs_growfs ${device}1 ;;
        *) echo '⚠️ Невідома ФС, спробуйте вручну'; exit 1 ;;
      esac
    " || error "❌ Помилка resize у VM '$vm'"
}

resize_in_vm "${VM_NAME:-$TMP_VM}"

log "🎉 Розширення файлової системи завершено успішно"
