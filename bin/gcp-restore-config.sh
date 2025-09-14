#!/bin/bash

# 🛠️ GCP Restore VM Config from JSON - оновлює існуючу VM на основі JSON конфігу

set -e

# 🎨 Кольори для логів
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()   { echo -e "${YELLOW}[⚠️]${NC} $1"; }
error()  { echo -e "${RED}[✖]${NC} $1" >&2; exit 1; }
confirm() {
  echo -en "${YELLOW}[❓]${NC} $1 [y/N]: "
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ====== Аргументи ======
for arg in "$@"; do
  case $arg in
    --config=*) CONFIG_FILE="${arg#*=}"; shift ;;
    --vm=*) VM_NAME="${arg#*=}"; shift ;;
    --zone=*) ZONE="${arg#*=}"; shift ;;
    --log-file=*) LOG_FILE="${arg#*=}"; shift ;;
    *) error "Невідомий параметр: $arg" ;;
  esac
done

[[ -z "$CONFIG_FILE" ]] && error "❌ Потрібно вказати --config=path/to/config.json"
[[ ! -f "$CONFIG_FILE" ]] && error "❌ Файл конфігурації не знайдено: $CONFIG_FILE"

# Автоотримання VM_NAME і ZONE з конфігу, якщо не задані явно
VM_NAME="${VM_NAME:-$(jq -r '.name' "$CONFIG_FILE")}"
ZONE="${ZONE:-$(jq -r '.zone' "$CONFIG_FILE")}"

[[ -z "$VM_NAME" || -z "$ZONE" ]] && error "❌ Не вдалося визначити VM_NAME або ZONE"

if [[ -n "$LOG_FILE" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

log "Відновлення конфігурації для VM: $VM_NAME у зоні $ZONE"

# Перевірка існування VM
if ! gcloud compute instances describe "$VM_NAME" --zone="$ZONE" &>/dev/null; then
  error "❌ Віртуальна машина $VM_NAME не існує у зоні $ZONE"
fi

# Перевірка статусу VM
STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format="get(status)")

# --- Функція для resize диска при необхідності ---
resize_disk_if_needed() {
  local disk_name="$1"
  local expected_size_gb="$2"

  # Отримуємо фактичний розмір диска в GCP
  local actual_size_gb
  actual_size_gb=$(gcloud compute disks describe "$disk_name" --zone="$ZONE" --format="value(sizeGb)") || {
    warn "Не вдалося отримати розмір диска $disk_name"
    return
  }

  if (( actual_size_gb < expected_size_gb )); then
    error "🚨 Розмір диска $disk_name ($actual_size_gb GB) менший за очікуваний $expected_size_gb GB — відновлення неможливе."
  elif (( actual_size_gb > expected_size_gb )); then
    warn "⚠️ Розмір диска $disk_name збільшено на $((actual_size_gb - expected_size_gb)) GB. Потрібно зробити resize файлової системи."

    if [[ "$STATUS" != "RUNNING" ]]; then
      error "VM $VM_NAME не запущена. Запустіть VM перед автоматичним resize файлової системи."
    fi

    log "📈 Виконуємо growpart і resize2fs на VM $VM_NAME для диска $disk_name"
    gcloud compute ssh "$VM_NAME" --zone="$ZONE" --quiet --command="
      set -e
      disk_dev=\$(ls /dev/disk/by-id/google-$disk_name 2>/dev/null || echo '')
      if [[ -z \"\$disk_dev\" ]]; then
        echo 'Не знайдено пристрій для диска $disk_name'
        exit 1
      fi
      sudo growpart \$disk_dev 1
      sudo resize2fs \${disk_dev}1
    " || warn "⚠️ Не вдалося автоматично розширити файлову систему диска $disk_name"

    log "✅ Resize файлової системи завершено"
  else
    log "Розмір диска $disk_name відповідає конфігу — resize не потрібен"
  fi
}

# --- Відновлення метаданих ---
update_metadata() {
  local meta=$(jq -r '.metadata.items[]? | "\(.key)=\(.value)"' "$CONFIG_FILE" 2>/dev/null || true)
  if [[ -n "$meta" ]]; then
    log "Оновлюємо метадані..."
    gcloud compute instances add-metadata "$VM_NAME" --zone="$ZONE" --metadata "$meta"
    log "Метадані оновлені"
  else
    warn "Метадані відсутні або не оновлюються"
  fi
}

# --- Відновлення тегів ---
update_tags() {
  local tags=$(jq -r '.tags.items | join(",")' "$CONFIG_FILE" 2>/dev/null || true)
  if [[ -n "$tags" ]]; then
    log "Оновлюємо теги..."
    gcloud compute instances add-tags "$VM_NAME" --zone="$ZONE" --tags "$tags"
    log "Теги оновлені"
  else
    warn "Теги відсутні або не оновлюються"
  fi
}

# --- Відновлення лейблів ---
update_labels() {
  # Отримати поточні лейбли у JSON
  current_labels_json=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format=json | jq '.labels // {}')

  # Отримати нові лейбли з конфігу (JSON обʼєкт)
  new_labels_json=$(jq '.labels // {}' "$CONFIG_FILE")

  # Злити лейбли, де нові мають пріоритет
  merged_labels_json=$(jq -s '.[0] * .[1]' <(echo "$current_labels_json") <(echo "$new_labels_json"))

  # Конвертуємо у key=value,key2=value2
  labels_str=$(echo "$merged_labels_json" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')

  if [[ -z "$labels_str" ]]; then
    warn "Лейбли відсутні або не оновлюються"
    return
  fi

  log "Оновлюємо лейбли..."
  gcloud compute instances update "$VM_NAME" --zone="$ZONE" --update-labels="$labels_str"
  log "Лейбли оновлені"
}

# --- Відновлення scheduling (automaticRestart, onHostMaintenance, preemptible) ---
update_scheduling() {
  local autoRestart=$(jq -r '.scheduling.automaticRestart // empty' "$CONFIG_FILE")
  local onHostMaintenance=$(jq -r '.scheduling.onHostMaintenance // empty' "$CONFIG_FILE")
  local preemptible=$(jq -r '.scheduling.preemptible // empty' "$CONFIG_FILE")

  if [[ -n "$autoRestart" || -n "$onHostMaintenance" || -n "$preemptible" ]]; then
    log "Оновлюємо scheduling..."
    # VM має бути вимкнена для зміни деяких scheduling опцій
    if [[ "$STATUS" == "RUNNING" ]]; then
      if confirm "VM запущена. Зупинити для оновлення scheduling?"; then
        gcloud compute instances stop "$VM_NAME" --zone="$ZONE"
        log "VM зупинена"
      else
        warn "Пропускаємо оновлення scheduling"
        return
      fi
    fi
    CMD=(gcloud compute instances update "$VM_NAME" --zone="$ZONE")
    [[ -n "$autoRestart" ]] && CMD+=(--automatic-restart="$autoRestart")
    [[ -n "$onHostMaintenance" ]] && CMD+=(--maintenance-policy="$onHostMaintenance")
    [[ -n "$preemptible" && "$preemptible" == "true" ]] && CMD+=(--preemptible)
    "${CMD[@]}"
    log "Scheduling оновлено"
  else
    warn "Scheduling параметри відсутні або не оновлюються"
  fi
}

# --- Відновлення machine-type (потребує зупинки VM) ---
update_machine_type() {
  local machineType=$(jq -r '.machineType' "$CONFIG_FILE" | awk -F/ '{print $NF}')
  if [[ -n "$machineType" ]]; then
    if [[ "$STATUS" == "RUNNING" ]]; then
      if confirm "VM запущена. Зупинити для зміни machine-type?"; then
        gcloud compute instances stop "$VM_NAME" --zone="$ZONE"
        log "VM зупинена"
      else
        warn "Пропускаємо оновлення machine-type"
        return
      fi
    fi
    gcloud compute instances set-machine-type "$VM_NAME" --zone="$ZONE" --machine-type="$machineType"
    log "Machine-type оновлено"
  else
    warn "Machine-type відсутній у конфігу"
  fi
}

# --- Відновлення дисків (підключення/відключення) ---
update_disks() {
  local disksConfig=$(jq -c '.disks[]' "$CONFIG_FILE")
  local currentDisks=$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format="value(disks.deviceName)")

  for diskJson in $disksConfig; do
    local deviceName=$(jq -r '.deviceName' <<< "$diskJson")
    local boot=$(jq -r '.boot' <<< "$diskJson")
    local size=$(jq -r '.initializeParams.diskSizeGb' <<< "$diskJson")
    local type=$(jq -r '.initializeParams.diskType' <<< "$diskJson")
    log "Обробка диска $deviceName"

    if ! gcloud compute disks describe "$deviceName" --zone="$ZONE" &>/dev/null; then
      log "Створюємо диск $deviceName"
      gcloud compute disks create "$deviceName" --size="${size}GB" --type="$type" --zone="$ZONE"
      log "Диск $deviceName створено"
    fi

    if ! echo "$currentDisks" | grep -q "$deviceName"; then
      log "Підключаємо диск $deviceName"
      local attachCmd=(gcloud compute instances attach-disk "$VM_NAME" --disk="$deviceName" --zone="$ZONE")
      [[ "$boot" == "true" ]] && attachCmd+=(--boot)
      "${attachCmd[@]}"
      log "Диск $deviceName підключено"
    fi
	
	# --- Виклик resize, якщо треба ---
    resize_disk_if_needed "$deviceName" "$size"
  done

  # Від’єднання зайвих дисків (опціонально)
  if confirm "Від’єднати зайві диски, не вказані у конфігу?"; then
    for curDisk in $currentDisks; do
      if ! jq -r '.disks[].deviceName' "$CONFIG_FILE" | grep -q "^$curDisk$"; then
        log "Від’єднуємо диск $curDisk"
        gcloud compute instances detach-disk "$VM_NAME" --disk="$curDisk" --zone="$ZONE"
        log "Диск $curDisk від’єднано"
      fi
    done
  fi
}

# --- Запуск VM після оновлення ---
start_vm() {
  if [[ "$STATUS" != "RUNNING" ]]; then
    if confirm "Запустити VM після відновлення?"; then
      gcloud compute instances start "$VM_NAME" --zone="$ZONE"
      log "VM запущена"
    fi
  else
    log "VM вже запущена"
  fi
}

# --- Основний процес ---
update_metadata
update_tags
update_labels
update_scheduling
update_machine_type
update_disks
start_vm

log "✅ Відновлення конфігурації VM завершено"
