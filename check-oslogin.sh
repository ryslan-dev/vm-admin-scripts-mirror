#!/bin/bash
# check-oslogin.sh
# Скрипт перевірки стану OS Login у Google Cloud VM

set -euo pipefail

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log_success(){ echo -e "${GREEN}[✔]${NC} $*" >&2; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $*" >&2; }
log_error()  { echo -e "${RED}[✘]${NC} $*" >&2; }

# 🛑 Root перевірка
if [[ "$EUID" -ne 0 ]]; then
  log_error "Для роботи скрипта потрібні права root"
  exit 1
fi

# 1. Отримати дані про метадані VM
VM_OSLOGIN_VALUE=$(curl -fs -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/enable-oslogin 2>/dev/null || echo "")
if [[ -z "$VM_OSLOGIN_VALUE" ]]; then
    VM_OSLOGIN=false
else
	VM_OSLOGIN="$VM_OSLOGIN_VALUE"
fi

# 2. Отримати дані про метадані проекту
PROJECT_OSLOGIN_VALUE=$(curl -fs -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/project/attributes/enable-oslogin 2>/dev/null || echo "")
if [[ -z "$PROJECT_OSLOGIN_VALUE" ]]; then
    PROJECT_OSLOGIN=false
else
	PROJECT_OSLOGIN="$PROJECT_OSLOGIN_VALUE"
fi

# 3. Перевірка sudoers-файлів
SUDOERS_OSLOGIN=false
[ -f /etc/sudoers.d/google-oslogin ] && SUDOERS_OSLOGIN=true
[ -d /var/google-sudoers.d ] && SUDOERS_OSLOGIN=true

VM_OSLOGIN=$(echo "$VM_OSLOGIN" | tr '[:upper:]' '[:lower:]')
PROJECT_OSLOGIN=$(echo "$PROJECT_OSLOGIN" | tr '[:upper:]' '[:lower:]')

echo "=== OS Login status check ==="
echo "Instance-level OS Login: $VM_OSLOGIN"
echo "Project-level  OS Login : $PROJECT_OSLOGIN"
echo "OS Login sudoers : $SUDOERS_OSLOGIN"
echo "============================="

# 4. Висновок
if [[ "$VM_OSLOGIN" == "true" || "$PROJECT_OSLOGIN" == "true" || "$SUDOERS_OSLOGIN" == "true" ]]; then
    log_success "OS Login схоже УВІМКНЕНО."
else
    log_warn "OS Login схоже ВИМКНЕНО. Використовується google-sudoers / локальні sudoers."
fi
