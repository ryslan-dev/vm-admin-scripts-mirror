#!/bin/bash
# get_users.sh
# Повний список sudo-користувачів на системі

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

declare -A users

for f in /etc/sudoers /etc/sudoers.d/*; do
    [[ -f "$f" ]] || continue
    while read -r entry; do
		# Якщо це псевдонім — пропускаємо
		[[ "$entry" == *"="* ]] && continue

        # Якщо це група (%group)
        if [[ "$entry" =~ ^% ]]; then
            group="${entry#%}"
            for u in $(getent group "$group" | awk -F: '{print $4}' | tr ',' ' '); do
                [[ -n "$u" ]] && users[$u]=1
            done
        else
            users[$entry]=1
        fi
    done < <(grep -E '^[^#].*ALL=\(ALL' "$f" | awk '{print $1}')
done

for u in "${!users[@]}"; do
    echo "$u"
done | sort -u