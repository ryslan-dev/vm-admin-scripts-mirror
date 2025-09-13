#!/bin/bash
# get-sudo-groups.sh
# Повний список груп, яким надано sudo-доступ у системі

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
CYAN='\033[96m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}(i) ${NC} $*" >&2; }
log_success() { echo -e "${GREEN}✔ ${NC} $*" >&2; }
log_warn() 	  { echo -e "${YELLOW}⚠️ ${NC} $*" >&2; }
log_error()   { echo -e "${RED}✖ ${NC} $*" >&2; }

# 🛑 Root перевірка
if [[ "$EUID" -ne 0 ]]; then
  log_error "Для роботи скрипта потрібні права root"
  exit 1
fi

declare -A groups

for f in /etc/sudoers /etc/sudoers.d/*; do
    [[ -f "$f" ]] || continue
    while read -r entry; do
        # Якщо це псевдонім — пропускаємо
        [[ "$entry" == *"="* ]] && continue

        # Якщо це група (%group)
        if [[ "$entry" =~ ^% ]]; then
            group="${entry#%}"
            groups[$group]=1
        fi
    done < <(grep -E '^[^#].*ALL=\(ALL' "$f" | awk '{print $1}')
done

for g in "${!groups[@]}"; do
    echo "$g"
done | sort -u