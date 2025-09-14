#!/bin/bash
# gcp-create-template-from-config.sh
# 🪄 Створює Instance Template із JSON-конфігурації
# Два режими: універсальний (default) та single (для шаблону конкретної VM)

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
  if [[ -f "${TMP_JSON:-}" ]]; then
    rm -f "$TMP_JSON"
    log "🧹 Тимчасовий файл $TMP_JSON видалено"
  fi
}

trap cleanup EXIT

# ====== Аргументи ======
SINGLE_MODE=0
SINGLE_MODE_NEW_DISK=0

for arg in "$@"; do
  case $arg in
    --config=*) CONFIG_JSON="${arg#*=}" ;;
    --template=*) TEMPLATE_NAME="${arg#*=}" ;;
    --project=*) PROJECT="${arg#*=}" ;;
	--zone=*) ZONE="${arg#*=}" ;;
    --os-image=*) OS_IMAGE_OVERRIDE="${arg#*=}" ;;
    --log-file=*) LOG_FILE="${arg#*=}" ;;
    --single|--single-instance) SINGLE_MODE=1 ;;
    *) error "Невідомий параметр: $arg" ;;
  esac
done

[[ -z "${CONFIG_JSON:-}" ]] && error "❌ Вкажіть --config=path/to/config.json"
[[ ! -f "$CONFIG_JSON" ]] && error "❌ Файл конфігурації не знайдено: $CONFIG_JSON"

PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null || echo "")}"
[[ -z "$PROJECT" ]] && error "❌ Не вказано проект і не задано у gcloud config"
ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "")}"
[[ -z "$ZONE" ]] && error "❌ Не вказано зону і не задано у gcloud config"

if [[ -n "${LOG_FILE:-}" ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

if (( SINGLE_MODE == 0 )); then
	IS_NEW_DISK=1
fi

# ====== Отримуємо список CLI параметрів ======
log "📥 Отримуємо список CLI параметрів із gcloud..."
ALLOWED_CLI_PARAMS=$(gcloud compute instance-templates create --help \
  | grep -Eo -- '--[a-zA-Z0-9\-]+' \
  | sed 's/^--//' | sort -u)

# ====== Допоміжні функції ======

# Витягти коротке ім'я з URL, якщо це URL
short_name() {
  local url="$1"
  if [[ "$url" =~ /([^/]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$url"
  fi
}

# Конвертує boolean automaticRestart в maintenance-policy
get_maintenance_policy() {
  local ar="$1"
  # у JSON true означає MIGRATE, false - TERMINATE
  if [[ "$ar" == "true" ]]; then
    echo "MIGRATE"
  else
    echo "TERMINATE"
  fi
}

# Форматування масиву ключ-значення для metadata/labels у CLI формат
format_key_value_list() {
  # $1 - JSON масив об’єктів виду {"key": "...", "value": "..."} або словник
  local json_val="$1"
  echo "$json_val" | jq -r '
    if type=="array" then
      map("\(.key)=\(.value|tostring)") | join(",")
    else
      to_entries | map("\(.key)=\(.value|tostring)") | join(",")
    end
  '
}

# Авто-форматування значень
auto_format_value() {
  local val="$1"
  local cli_param="$2"
  local t=$(echo "$val" | jq -r 'type')

  case "$cli_param" in
    tags|scopes)
      echo "$val" | jq -r '. | join(",")'
      ;;
    metadata|labels)
      echo "$val" | jq -r 'to_entries | map("\(.key)=\(.value|tostring)") | join(",")'
      ;;
    *)
      case "$t" in
        string|number|boolean) echo "$val" | jq -r '.' ;;
        array) echo "$val" | jq -r '. | join(",")' ;;
        object)
          echo "$val" | jq -r 'to_entries | map("\(.key)=\(.value|tostring)") | join(",")'
          ;;
        *) warn "⚠️ Невідомий тип для $cli_param: $t"; echo "$val" | jq -r '.' ;;
      esac
      ;;
  esac
}

# ====== Перевірка SINGLE_MODE доступності диска ======
if (( SINGLE_MODE == 1 )); then
  disk_uri=$(jq -r '.disks[0].source // empty' "$CONFIG_JSON")
  if [[ -n "$disk_uri" ]]; then
    disk_project=$(echo "$disk_uri" | awk -F/ '{print $4}')
    disk_zone=$(echo "$disk_uri" | awk -F/ '{print $6}')
    disk_name=$(echo "$disk_uri" | awk -F/ '{print $8}')

    log "ℹ️ Диск у JSON: $disk_name (проект: $disk_project, зона: $disk_zone)"
    log "ℹ️ Параметри скрипта: проект=$PROJECT зона=$ZONE"

    if [[ "$disk_project" != "$PROJECT" || "$disk_zone" != "$ZONE" ]]; then
      warn "⚠️ Диск у іншому проекті/зоні. Тому диск буде новий."
      IS_NEW_DISK=1
    else
      log "✅ Диск доступний у проекті/зоні."
    fi
  else
    warn "⚠️ У JSON не знайдено disks[0].source. Тому диск буде новий."
    IS_NEW_DISK=1
  fi
fi

# Додаємо новий диск якщо потрібно
if (( IS_NEW_DISK == 1 )); then
  has_disk_source=$(jq -r '.disks[0].source // empty' "$CONFIG_JSON")
  if [[ -n "$has_disk_source" ]]; then
    log "ℹ️ Виявлено .disks[0].source, замінюємо на initializeParams"
    # Замінимо в JSON вхідні значення для image, diskSizeGb, diskType з initializeParams
    # Щоб у скрипті не міняти, перепишемо у тимчасовий файл
	TMP_JSON=$(mktemp)
    jq '
      .disks[0] |=
        (. + {
          "initializeParams": {
            "sourceImage": (.initializeParams.sourceImage // ""),
            "diskSizeGb": (.initializeParams.diskSizeGb // ""),
            "diskType": (.initializeParams.diskType // "")
          }
        }) |
      del(.disks[0].source)
    ' "$CONFIG_JSON" > "$TMP_JSON"
    CONFIG_JSON="$TMP_JSON"
  fi
fi

# ====== JSON_MAP: CLI → JSON ключ ======
declare -A JSON_MAP=(
  ["machine-type"]="machineType"
  ["image"]="disks[0].initializeParams.sourceImage"
  ["boot-disk-size"]="disks[0].initializeParams.diskSizeGb"
  ["boot-disk-type"]="disks[0].initializeParams.diskType"
  ["tags"]="tags.items"
  ["metadata"]="metadata.items"
  ["labels"]="labels"
  ["network"]="networkInterfaces[0].network"
  ["subnet"]="networkInterfaces[0].subnetwork"
  ["deletion-protection"]="deletionProtection"
  ["service-account"]="serviceAccounts[0].email"
  ["scopes"]="serviceAccounts[0].scopes"
  ["preemptible"]="scheduling.preemptible"
  ["maintenance-policy"]="scheduling.automaticRestart"
)

# ====== Формуємо список аргументів ======
ARGS=()

for cli_param in $ALLOWED_CLI_PARAMS; do
  json_key="${JSON_MAP[$cli_param]:-}"

  # Авто-пошук JSON ключа, якщо немає у мапі
  if [[ -z "$json_key" ]]; then
    json_key_guess=$(echo "$cli_param" | tr '-' '.')
    raw_guess=$(jq -c ".${json_key_guess} // empty" "$CONFIG_JSON")
    if [[ -n "$raw_guess" && "$raw_guess" != "null" ]]; then
      warn "⚠️ Авто-виявлення: використано ${json_key_guess} для --${cli_param}"
      json_key="$json_key_guess"
    fi
  fi

  if [[ -n "$json_key" ]]; then
    raw_value=$(jq -c ".${json_key} // empty" "$CONFIG_JSON")
    if [[ -n "$raw_value" && "$raw_value" != "null" ]]; then

      # універсальний режим - трансформації
      case "$cli_param" in
          machine-type|network|subnet)
            short=$(jq -r ".${json_key}" "$CONFIG_JSON" | xargs -n1 short_name)
            formatted_value="$short"
            ;;
          maintenance-policy)
            raw_bool=$(jq -r ".${json_key}" "$CONFIG_JSON")
            formatted_value=$(get_maintenance_policy "$raw_bool")
            ;;
          tags|scopes)
            formatted_value=$(echo "$raw_value" | jq -r '. | join(",")')
            ;;
          metadata|labels)
            formatted_value=$(format_key_value_list "$raw_value")
            ;;
          *)
            formatted_value=$(auto_format_value "$raw_value" "$cli_param")
            ;;
      esac

      ARGS+=("--${cli_param}=${formatted_value}")
      log "✅ --${cli_param}=${formatted_value}"
    else
      log "ℹ️ Пропускаємо --${cli_param}: значення відсутнє у JSON"
    fi
  else
    warn "⚠️ --${cli_param}: немає мапінгу і не знайдено авто-відповідність у JSON"
  fi
done

# ====== Додаємо OS image, якщо потрібно ======
if (( IS_NEW_DISK == 1 )); then
  OS_IMAGE=$(jq -r '.disks[0].initializeParams.sourceImage // empty' "$CONFIG_JSON")
  if [[ -n "${OS_IMAGE_OVERRIDE:-}" ]]; then
    OS_IMAGE="$OS_IMAGE_OVERRIDE"
  fi
  if [[ -z "$OS_IMAGE" ]]; then
    OS_IMAGE="projects/debian-cloud/global/images/family/debian-12"
    warn "⚠️ Образ ОС не вказано, використовуємо дефолт: $OS_IMAGE"
  fi

  if ! printf '%s\n' "${ARGS[@]}" | grep -q -- '--image='; then
    ARGS+=("--image=${OS_IMAGE}")
    log "🟢 Додаємо дефолтний --image=${OS_IMAGE}"
  fi
else
  log "ℹ️ Режим single: пропускаємо додавання --image, оскільки диск вже існує"
fi

# ====== Назва шаблону ======
VM_NAME=$(jq -r '.name' "$CONFIG_JSON")
if [[ -z "${TEMPLATE_NAME:-}" ]]; then
  DATE=$(date +'%Y-%m-%d-%H-%M-%S')
  TEMPLATE_NAME="${VM_NAME}-template-${DATE}"
fi

log "🚀 Створюємо шаблон: $TEMPLATE_NAME"
log "📦 Проєкт: $PROJECT"

# ====== Викликаємо gcloud ======
gcloud compute instance-templates create "$TEMPLATE_NAME" \
  --project="$PROJECT" \
  "${ARGS[@]}" || error "❌ Не вдалося створити шаблон"

log "✅ Шаблон '$TEMPLATE_NAME' створено успішно"