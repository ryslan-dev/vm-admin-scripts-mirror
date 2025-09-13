#!/bin/bash

# 🛠️ GCP Restore Disk - відновлює диск зі snapshot, image, archive або gs:// і підключає до VM

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

# ====== Аргументи ======
for arg in "$@"; do
  case $arg in
    --source=*) SOURCE_NAME="${arg#*=}" ;;
    --disk=*) DISK_NAME="${arg#*=}" ;;
    --type=*) DISK_TYPE="${arg#*=}" ;;
    --size=*) DISK_SIZE="${arg#*=}" ;;
    --boot) IS_BOOT=true ;;
    --vm=*) VM_NAME="${arg#*=}" ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    --log-file=*) LOG_FILE="${arg#*=}" ;;
    *) error "❌ Невідомий параметр $arg" ;;
  esac
done

# 📜 Лог-файл
if [[ -n "${LOG_FILE:-}" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

# 🧾 Перевірка обов'язкових параметрів
[[ -z "${SOURCE_NAME:-}" ]] && error "❌ Вкажіть джерело через --source=SNAPSHOT|IMAGE|ARCHIVE|gs://FILE"
[[ -z "${DISK_NAME:-}" ]] && error "❌ Вкажіть назву диска через --disk=DISK_NAME"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
[[ -z "$ZONE" ]] && error "❌ Не вказано зону і не знайдено значення за замовчуванням"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект і не знайдено значення за замовчуванням"

# 📌 Визначаємо чи новий диск буде boot
if [[ -n "${VM_NAME:-}" ]]; then
  
  log "🔎 Визначаємо чи новий диск буде boot"
  
  if [[ "${IS_BOOT:-}" == true ]]; then
    
	log "⚡ Вказано --boot: новий диск буде boot"
    IS_BOOT=true
  else

    BOOT_DISK=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" \
    --format="value(disks[?boot=true].deviceName)")
	
	if [[ "$DISK_NAME" == "$BOOT_DISK" ]]; then
      
	  log "🔍 Старий диск є boot: новий диск також буде boot"
      IS_BOOT=true
    else
      
	  log "📦 Старий диск – data: новий диск буде data-диском"
      IS_BOOT=false
    fi
  fi
fi

# ⚠️ Перевірка чи диск з такою назвою вже існує
if gcloud compute disks list --filter="name=($DISK_NAME)" --format="value(name)" | grep -q "$DISK_NAME"; then
  warn "Диск з назвою '$DISK_NAME' вже існує в $ZONE"
  if confirm "Видалити існуючий диск '$DISK_NAME' і створити новий?"; then
    gcloud compute disks delete "$DISK_NAME" --zone="$ZONE" --project="$PROJECT" --quiet \
      || error "❌ Не вдалося видалити існуючий диск"
    log "🗑️ Старий диск '$DISK_NAME' видалено"
  else
    # Перейменування: створюємо копію з новою назвою (з датою)
    OLD_DISK_NAME="${DISK_NAME}-$(date +'%Y-%m-%d-%H-%M-%S')"
    log "📦 Перейменовуємо старий диск $DISK_NAME у $OLD_DISK_NAME"

    # Використовуємо gcp-create-disk для створення копії диска
    gcp-create-disk \
      --source="projects/$PROJECT/zones/$ZONE/disks/$DISK_NAME" \
      --disk="$OLD_DISK_NAME" \
      --zone="$ZONE" \
      --project="$PROJECT" \
	  --skip-fs-resize \
      || error "❌ Не вдалося створити копію старого диска як $OLD_DISK_NAME"

    # Після успішного копіювання видаляємо старий диск
    gcloud compute disks delete "$DISK_NAME" --zone="$ZONE" --project="$PROJECT" --quiet \
      || error "❌ Не вдалося видалити старий диск $DISK_NAME після копіювання"

    log "✅ Старий диск перейменовано у $OLD_DISK_NAME"
  fi
fi


# 🚀 Створюємо новий диск
log "💽 Створюємо диск '$DISK_NAME' зі $SOURCE_NAME"
gcp-create-disk \
  --source="$SOURCE_NAME" \
  --disk="$DISK_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT" \
  --skip-fs-resize \
  ${DISK_SIZE:+--size="$DISK_SIZE"} \
  ${DISK_TYPE:+--type="$DISK_TYPE"} \
  || error "❌ Не вдалося створити новий диск"

log "✅ Диск '$DISK_NAME' створено успішно"

# 🔥 Якщо вказана VM – підключаємо диск
if [[ -n "${VM_NAME:-}" ]]; then

  # 📌 Підключаємо новий диск
  log "🔗 Підключаємо новий диск '$DISK_NAME' до VM '$VM_NAME'"
  if [[ "$IS_BOOT" == true ]]; then
    gcloud compute instances attach-disk "$VM_NAME" \
      --disk="$DISK_NAME" --zone="$ZONE" --boot --device-name="$DISK_NAME" \
      || error "❌ Не вдалося підключити '$DISK_NAME' як boot"
    log "✅ Диск '$DISK_NAME' підключено як boot"
  else
    gcloud compute instances attach-disk "$VM_NAME" \
      --disk="$DISK_NAME" --zone="$ZONE" \
      || error "❌ Не вдалося підключити '$DISK_NAME' як data-диск"
    log "✅ Диск '$DISK_NAME' підключено як data"
  fi

fi

log "📈 Перевіряємо та розширюємо файлову систему (за потреби)"
gcp-resize-disk-fs \
  --disk="$DISK_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT" \
  "${VM_NAME:+--vm="$VM_NAME"}" \
  || error "❌ Помилка при перевірці/розширенні файлової системи"

log "🎉 Відновлення завершено: $DISK_NAME"
