#!/bin/bash
# gcp-create-instance.sh
# 🪄 Універсальний скрипт для:
# ✅ Клонування VM або Instance Template
# ✅ Створення VM зі шаблону
# ✅ Створення VM або шаблону з JSON-конфігурації
# ✅ Створення бекапу конфігурації VM або шаблону
# ✅ Підтримка override параметрів (machine-type, tags, metadata...)
# ✅ Підтримка режимів single/universal для шаблонів
# Для створення нового шаблону використовує gcp-create-template-from-config.sh

set -euo pipefail
IFS=$'\n\t'

# ====== Кольори для логів ======
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✔]${NC} $*"; }
warn()  { echo -e "${YELLOW}[⚠️]${NC} $*"; }
error() { echo -e "${RED}[✖]${NC} $*" >&2; exit 1; }

# ====== Cleanup ======
cleanup() {
  
  # Видаляємо тимчасовий JSON якщо створювали
  if [[ -f "${TMP_JSON:-}" ]]; then
    rm -f "$TMP_JSON"
    log "🧹 Тимчасовий файл $TMP_JSON видалено"
  fi
  
  # Видаляємо тимчасовий шаблон якщо створювали
  if [[ -n "${TMP_TEMPLATE:-}" && "${TMP_TEMPLATE_CREATED:-}" -eq 1 ]]; then
    log "🧹 Видаляємо тимчасовий шаблон '$TMP_TEMPLATE'..."
    set +e
    gcloud compute instance-templates delete "$TMP_TEMPLATE" --quiet --project="$PROJECT"
    if [[ $? -ne 0 ]]; then
      warn "⚠️ Не вдалося видалити тимчасовий шаблон"
    fi
    set -e
  fi
}
trap cleanup EXIT

# ====== Перевірка залежностей ======
[[ -x "$(command -v gcloud)" ]] || error "❌ Не знайдено gcloud"
[[ -x "$(command -v jq)" ]] || error "❌ Не знайдено jq"
[[ -f "./gcp-create-template-from-config.sh" ]] || error "❌ Не знайдено gcp-create-template-from-config.sh у поточній директорії"

# ====== Аргументи ======
SINGLE_MODE=0
declare -A OVERRIDES
DISKS_OVERRIDE_RAW=""

for arg in "$@"; do
  case $arg in
    --source-instance=*) SOURCE_INSTANCE="${arg#*=}" ;;
    --source-template=*) SOURCE_TEMPLATE="${arg#*=}" ;;
    --source-config=*) SOURCE_CONFIG="${arg#*=}" ;;
    --new-instance=*) NEW_INSTANCE="${arg#*=}" ;;
    --new-template=*) NEW_TEMPLATE="${arg#*=}" ;;
    --new-config=*) NEW_CONFIG="${arg#*=}" ;;
    --single|--single-instance) SINGLE_MODE=1 ;;
    --zone=*) ZONE="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
    --disks=*)
      DISKS_OVERRIDE_RAW="${arg#*=}"
      ;;
    --*=*)
      key="${arg%%=*}"
      val="${arg#*=}"
      key="${key#--}"
	  # Пропускаємо disks, бо обробляємо окремо
      if [[ "$key" != "disks" ]]; then
        OVERRIDES["$key"]="$val"
      fi
      ;;
    *)
      error "❌ Невідомий параметр: $arg"
      ;;
  esac
done

# ====== Перевірка джерел ======
SOURCE_COUNT=0
[[ -n "${SOURCE_INSTANCE:-}" ]] && ((SOURCE_COUNT++))
[[ -n "${SOURCE_TEMPLATE:-}" ]] && ((SOURCE_COUNT++))
[[ -n "${SOURCE_CONFIG:-}" ]] && ((SOURCE_COUNT++))

[[ $SOURCE_COUNT -eq 0 ]] && error "❌ Вкажіть джерело: --source-instance, --source-template або --source-config"
[[ $SOURCE_COUNT -gt 1 ]] && error "❌ Вкажіть тільки одне джерело"

# ====== Перевірка проекту та зони ======
PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null || echo "")}"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект і не задано у gcloud config"

ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "")}"
[[ -z "$ZONE" ]] && error "❌ Не вказано зону і не задано у gcloud config"

# ====== Перевірка overrides ======
has_overrides() {
  [[ ${#OVERRIDES[@]} -gt 0 ]]
}

# ====== Функції ======

# Перевірка чи існує диск
disk_exists() {
  local disk_name=$1
  local zone=$2
  gcloud compute disks describe "$disk_name" --zone="$zone" --project="$PROJECT" &>/dev/null
}

# Запит користувачу на створення нового диска, якщо відсутній
prompt_create_disk() {
  local disk_name=$1
  echo
  read -rp "❓ Диск '$disk_name' не знайдено. Створити новий диск типу pd-ssd 50GB? (y/n): " ans
  case "$ans" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

# Створення нового диска з дефолтними параметрами
create_disk() {
  local disk_name=$1
  local zone=$2
  log "📀 Створюємо диск '$disk_name' типу pd-ssd розміром 10GB у зоні $zone..."
  gcloud compute disks create "$disk_name" --type=pd-ssd --size=10GB --zone="$zone" --project="$PROJECT" || {
    error "❌ Не вдалося створити диск '$disk_name'"
  }
  log "✅ Диск '$disk_name' створено."
}

# Отримання списку дисків з JSON (парсинг)
# Повертає рядки у форматі: deviceName boot autoDelete diskName
parse_disks_from_json() {
  local json_file=$1
  jq -r '
    .disks[] | 
    [
      .deviceName,
      (.boot // false),
      (.autoDelete // false),
      (.source | split("/") | .[-1])
    ] | @tsv' "$json_file"
}

# Формує аргументи --disk= для gcloud create instance
# Формат рядка: deviceName boot autoDelete diskName
generate_disk_args() {
  local deviceName=$1
  local boot=$2
  local autoDelete=$3
  local diskName=$4

  local arg="name=$diskName"
  arg+=",boot=$( [[ $boot == true ]] && echo yes || echo no )"
  arg+=",auto-delete=$( [[ $autoDelete == true ]] && echo yes || echo no )"

  # Додаткові параметри можна додати сюди, наприклад mode=rw
  echo "$arg"
}

# ====== Обробка дисків із параметра --disks= =====
process_disks_override() {
  # Виконуємо обробку DISKS_OVERRIDE_RAW, оновлюємо TMP_JSON
  local raw="$1"

  if [[ -z "$raw" ]]; then
    warn "⚠️ Параметр --disks передано без значення, пропускаємо."
    return 0
  fi

  log "⚙️ Застосовуємо override --disks..."

  # Перевіряємо, чи починається з [
  if [[ "$raw" =~ ^\[ ]]; then
    # Вважаємо, що це JSON-масив, перевіряємо валідність
    echo "$raw" | jq empty 2>/dev/null || error "❌ Некоректний JSON-масив у --disks"
    jq --argjson disks "$raw" '.disks = $disks' "$TMP_JSON" > "${TMP_JSON}.tmp" && mv "${TMP_JSON}.tmp" "$TMP_JSON"
    return 0
  fi

  # Якщо не JSON - парсимо як рядок дисків розділених ;
  IFS=';' read -ra disk_items <<< "$raw"
  disks_json="[]"
  for item in "${disk_items[@]}"; do
    declare -A params
    IFS=',' read -ra pairs <<< "$item"
    for pair in "${pairs[@]}"; do
      key="${pair%%=*}"
      val="${pair#*=}"
      # Перетворення yes/no у boolean
      if [[ "$val" == "yes" ]]; then val=true; elif [[ "$val" == "no" ]]; then val=false; fi
      params["$key"]="$val"
    done

    # Формуємо deviceName (перевага deviceName, якщо немає — name)
    deviceName="${params[deviceName]:-${params[name]}}"
    [[ -z "$deviceName" ]] && error "❌ В параметрах диска має бути вказано 'deviceName' або 'name'"

    boot=${params[boot]:-false}
    autoDelete=${params["auto-delete"]:-false}
    diskName="${params[name]:-$deviceName}"

    # Формуємо source
    source="projects/$PROJECT/zones/$ZONE/disks/$diskName"

    disk_obj=$(jq -n \
      --arg deviceName "$deviceName" \
      --arg source "$source" \
      --argjson boot "$boot" \
      --argjson autoDelete "$autoDelete" \
      '{
        deviceName: $deviceName,
        source: $source,
        boot: $boot,
        autoDelete: $autoDelete
      }')
    disks_json=$(jq --argjson disk "$disk_obj" '. + [$disk]' <<< "$disks_json")
  done

  jq --argjson disks "$disks_json" '.disks = $disks' "$TMP_JSON" > "${TMP_JSON}.tmp" && mv "${TMP_JSON}.tmp" "$TMP_JSON"
}

# ====== Функція для вибору дії при існуючому ресурсі ======
# Повертає у форматі choice|new_name
prompt_for_action() {
  local resource_key=$1
  local resource_name=$2
  local resource_label=""
  local input_prompt=""
  local delete_prompt=""

  case "$resource_key" in
    template)
      resource_label="шаблон"
      input_prompt="Введіть нове ім'я для шаблону"
      delete_prompt="Видалити існуючий шаблон"
      ;;
    instance)
      resource_label="VM"
      input_prompt="Введіть нове ім'я VM"
      delete_prompt="Видалити існуючу VM"
      ;;
    config)
      resource_label="конфігурацію"
      input_prompt="Введіть нову назву для файлу конфігурації"
      delete_prompt="Видалити існуючий файл конфігурації"
      ;;
    *)
      resource_label="$resource_key"
      input_prompt="Введіть нове ім'я для $resource_label"
      delete_prompt="Видалити існуючий $resource_label"
      ;;
  esac

  while true; do
    echo -e "\n⚠️ $resource_label з ім'ям '$resource_name' вже існує."
    echo "Оберіть дію:"
    echo "  d - $delete_prompt"
    echo "  n - $input_prompt"
    echo "  c - Скасувати операцію"
    read -rp "Ваш вибір (d/n/c): " choice

    case "$choice" in
      d|D)
        echo "d|$resource_name"
        return 0
        ;;
      n|N)
       while true; do
         read -rp "$input_prompt: " new_name
         if [[ -n "$new_name" ]]; then
           echo "n|$new_name"
           return 0
         else
           echo "Ім'я не може бути порожнім, спробуйте ще раз."
         fi
       done
       ;;
      c|C)
        echo "c|"
        return 0
        ;;
      *)
        echo "Невірний вибір, спробуйте ще раз."
        ;;
    esac
  done
}

# ====== Перевірка на існування ресурсу ======
resource_exists() {
  local type=$1
  local name=$2
  case "$type" in
    template)
      gcloud compute instance-templates describe "$name" --project="$PROJECT" &>/dev/null
      ;;
    instance)
      gcloud compute instances describe "$name" --zone="$ZONE" --project="$PROJECT" &>/dev/null
      ;;
    config)
      [[ -f "$name" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

# ====== Створення шаблону із JSON ======
create_template_from_config() {
  local CONFIG_JSON=$1
  local TEMPLATE_NAME=$2

  CMD=(./gcp-create-template-from-config.sh --config="$CONFIG_JSON" --template="$TEMPLATE_NAME" --project="$PROJECT")

  # Якщо потрібно режим single - передаємо --single
  if [[ "${SINGLE_MODE:-0}" -eq 1 ]]; then
    CMD+=(--single)
  fi

  "${CMD[@]}" || error "❌ Помилка створення нового шаблону '$TEMPLATE_NAME'"
}

# Перевірка існування ключа в JSON-файлі
check_override_key_exists() {
  local json_file=$1
  local key=$2

  jq --arg key "$key" '
    def parse_path(path):
      [capture("(?<head>[^.\\[]+)").head] +
      (path | scan("\\[(\\d+)\\]|\\.([^.\\[]+)") | map(if .[0] == "[" then (. | tonumber) else . end));
    getpath(parse_path($key)) != null
  ' "$json_file"
}

# ====== Основна логіка ======
TMP_JSON=$(mktemp)

# 📦 Отримуємо JSON конфігурацію
if [[ -n "${SOURCE_INSTANCE:-}" ]]; then
  log "📥 Отримуємо JSON конфігурацію VM '$SOURCE_INSTANCE'..."
  gcloud compute instances describe "$SOURCE_INSTANCE" \
    --project="$PROJECT" --zone="$ZONE" --format=json > "$TMP_JSON" || error "❌ Не вдалося отримати конфігурацію VM"

elif [[ -n "${SOURCE_TEMPLATE:-}" ]]; then
  log "📥 Отримуємо JSON конфігурацію шаблону '$SOURCE_TEMPLATE'..."
  gcloud compute instance-templates describe "$SOURCE_TEMPLATE" \
    --project="$PROJECT" --format=json > "$TMP_JSON" || error "❌ Не вдалося отримати конфігурацію шаблону"

elif [[ -n "${SOURCE_CONFIG:-}" ]]; then
  log "📥 Використовуємо локальний JSON '$SOURCE_CONFIG'..."
  cp "$SOURCE_CONFIG" "$TMP_JSON"
fi

# Застосовуємо overrides, окрім disks (вони окремо)
if has_overrides; then
  log "⚙️ Застосовуємо overrides до конфігурації..."
  for key in "${!OVERRIDES[@]}"; do
    val="${OVERRIDES[$key]}"
	
    # Перевіряємо чи існує ключ у JSON
    exists=$(check_override_key_exists "$TMP_JSON" "$key")
    if [[ "$exists" != "true" ]]; then
      warn "⚠️ Ключ override '$key' не знайдено у JSON конфігурації, буде доданий новий."
    fi	
	
    jq --arg key "$key" --arg val "$val" '
      def parse_path(path):
        [capture("(?<head>[^.\\[]+)").head] +
        (path | scan("\\[(\\d+)\\]|\\.([^.\\[]+)") | map(if .[0] == "[" then (. | tonumber) else . end));
      setpath(parse_path($key); $val)
    ' "$TMP_JSON" > "${TMP_JSON}.tmp" && mv "${TMP_JSON}.tmp" "$TMP_JSON"
  done
fi

# Якщо передано --disks, застосовуємо override і оновлюємо секцію дисків
if [[ -n "$DISKS_OVERRIDE_RAW" ]]; then
  process_disks_override "$DISKS_OVERRIDE_RAW"
fi

# Отримуємо список дисків з TMP_JSON
readarray -t DISKS_ARR < <(parse_disks_from_json "$TMP_JSON")
if [[ ${#DISKS_ARR[@]} -eq 0 ]]; then
  warn "⚠️ У конфігурації не знайдено дисків"
fi

# Перевірка та створення дисків за потребою
UPDATED_DISKS_JSON="[]"
for disk_line in "${DISKS_ARR[@]}"; do
  IFS=$'\t' read -r deviceName boot autoDelete diskName <<< "$disk_line"

  # Перевіряємо чи диск існує
  if ! disk_exists "$diskName" "$ZONE"; then
    if prompt_create_disk "$diskName"; then
      create_disk "$diskName" "$ZONE"
    else
      error "❌ Диск '$diskName' не існує і не створений. Скасування."
    fi
  fi

  # Формуємо оновлений блок для цього диска
  updated_disk=$(jq -n \
    --arg deviceName "$deviceName" \
    --arg source "projects/$PROJECT/zones/$ZONE/disks/$diskName" \
    --argjson boot "$boot" \
    --argjson autoDelete "$autoDelete" \
    '{
      deviceName: $deviceName,
      source: $source,
      boot: $boot,
      autoDelete: $autoDelete
    }')

  # Додаємо до масиву оновлених дисків
  UPDATED_DISKS_JSON=$(jq --argjson disk "$updated_disk" '. + [$disk]' <<< "$UPDATED_DISKS_JSON")
done

# Записуємо оновлені диски назад у TMP_JSON
jq --argjson disks "$UPDATED_DISKS_JSON" '.disks = $disks' "$TMP_JSON" > "${TMP_JSON}.tmp" && mv "${TMP_JSON}.tmp" "$TMP_JSON"
log "📦 Оновлено секцію дисків у TMP_JSON"

# 💾 Збереження конфігурації у файл, якщо потрібно
if [[ -n "${NEW_CONFIG:-}" ]]; then
  # Перевірка існування файлу конфігурації
  while resource_exists config "$NEW_CONFIG"; do
    action=$(prompt_for_action config "$NEW_CONFIG")
    choice="${action%%|*}"
    new_name="${action#*|}"

    case "$choice" in
      d)
        if [[ -f "$NEW_CONFIG" ]]; then
          rm -f "$NEW_CONFIG"
          log "✅ Існуючий файл конфігурації '$NEW_CONFIG' видалено."
        else
          warn "⚠️ Файл конфігурації '$NEW_CONFIG' не знайдено."
        fi
        break
        ;;
      n)
        NEW_CONFIG="$new_name"
        ;;
      c)
        error "Операцію скасовано користувачем."
        ;;
    esac
  done
  cp "$TMP_JSON" "$NEW_CONFIG"
  log "💾 Збережено конфігурацію у файл: $NEW_CONFIG"
fi

# 📦 Створюємо шаблон, якщо вказано --new-template
if [[ -n "${NEW_TEMPLATE:-}" ]]; then
  # Перевірка існування шаблону
  while resource_exists template "$NEW_TEMPLATE"; do
    action=$(prompt_for_action template "$NEW_TEMPLATE")
    choice="${action%%|*}"
    new_name="${action#*|}"

    case "$choice" in
      d)
        gcloud compute instance-templates delete "$NEW_TEMPLATE" --quiet --project="$PROJECT"
        log "✅ Існуючий шаблон '$NEW_TEMPLATE' видалено."
        break
        ;;
      n)
        NEW_TEMPLATE="$new_name"
        ;;
      c)
        error "Операцію скасовано користувачем."
        ;;
    esac
  done
  log "📦 Створюємо новий шаблон '$NEW_TEMPLATE'..."
  create_template_from_config "$TMP_JSON" "$NEW_TEMPLATE"
fi

# 🚀 Створюємо нову VM, якщо вказано --new-instance
if [[ -n "${NEW_INSTANCE:-}" ]]; then

  if [[ -z "$ZONE" ]]; then
    error "❌ Зона не вказана, неможливо створити VM"
  fi
  
  # Перевірка існування VM
  while resource_exists instance "$NEW_INSTANCE"; do
    action=$(prompt_for_action instance "$NEW_INSTANCE")
    choice="${action%%|*}"
    new_name="${action#*|}"

    case "$choice" in
      d)
        gcloud compute instances delete "$NEW_INSTANCE" --quiet --zone="$ZONE" --project="$PROJECT"
        log "✅ Існуюча VM '$NEW_INSTANCE' видалена."
        break
        ;;
      n)
        NEW_INSTANCE="$new_name"
        ;;
      c)
        error "Операцію скасовано користувачем."
        ;;
    esac
  done
  
  # Якщо шаблон не вказано, використовуємо TMP_JSON для створення тимчасового шаблону
  if [[ -z "${NEW_TEMPLATE:-}" ]]; then
    TMP_TEMPLATE="tmp-template-$(date +%s)"
    log "📦 Створюємо тимчасовий шаблон '$TMP_TEMPLATE' для VM..."
    create_template_from_config "$TMP_JSON" "$TMP_TEMPLATE"
    NEW_TEMPLATE="$TMP_TEMPLATE"
    TMP_TEMPLATE_CREATED=1
  else
    TMP_TEMPLATE_CREATED=0
  fi

  log "🚀 Створюємо нову VM '$NEW_INSTANCE' зі шаблону '$NEW_TEMPLATE'..."
  gcloud compute instances create "$NEW_INSTANCE" \
    --source-instance-template="$NEW_TEMPLATE" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    || error "❌ Не вдалося створити VM зі шаблону '$NEW_TEMPLATE'"
  log "✅ Нова VM '$NEW_INSTANCE' створена"
fi