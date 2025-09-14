#!/bin/bash
# Автоматичне налаштування tmux з глобальним конфігом

set -euo pipefail
IFS=$'\n\t'

NC='\033[0m'				# скидання кольору

RED='\033[91m'				# червоний
GREEN='\033[92m'			# зелений
YELLOW='\033[93m'			# жовтий

log_success() { echo -e "${GREEN}✔ ${NC} $*"; }
log_warn() 	  { echo -e "${YELLOW}⚠️ ${NC} $*"; }
log_error()   { echo -e "${RED}✖ ${NC} $*"; }

# ===================== CHECK REQUIREMENTS =====================
if ! command -v tmux &>/dev/null; then
    log_warn "Не знайдено: tmux"
    read -rp "Встановити tmux? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y tmux
        log_success "tmux встановлено"
    else
        log_error "❌  tmux є обов'язковим"
        exit 1
    fi
fi

CONFIG_FILE="/etc/tmux.conf"

# Якщо конфіг вже існує — нічого не робимо
if [ -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Вміст глобального конфіга
read -r -d '' TMUX_CONFIG <<'EOF'
# =============================
# Мінімальна конфігурація tmux
# =============================

# Замість Ctrl-b → Ctrl-a (зручніше, особливо на ноуті)
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Перемикання між панелями стрілками (з Ctrl)
bind -n C-Left  select-pane -L
bind -n C-Right select-pane -R
bind -n C-Up    select-pane -U
bind -n C-Down  select-pane -D

# Поділ панелей (як у mc)
bind | split-window -h    # Ctrl-a | → поділ вертикально (ліва/права)
bind - split-window -v    # Ctrl-a - → поділ горизонтально (верх/низ)

# Зручний resize панелей (Alt + стрілки)
bind -n M-Left  resize-pane -L 2
bind -n M-Right resize-pane -R 2
bind -n M-Up    resize-pane -U 1
bind -n M-Down  resize-pane -D 1

# Номери панелей (щоб знати, куди переключатись)
set -g pane-border-status top
set -g pane-border-format " #{pane_index} "

# Краще кольорове оформлення меж панелей
set -g pane-active-border-style "fg=green"
set -g pane-border-style "fg=grey"

# Мишка (можна кліком переключати панелі та міняти розмір)
set -g mouse on

# 256 кольорів
set -g default-terminal "screen-256color"
EOF

# Записуємо конфіг у /etc/tmux.conf
echo "⚙️  Налаштування $CONFIG_FILE ..."
echo "$TMUX_CONFIG" | sudo tee "$CONFIG_FILE" > /dev/null

log_success "Глобальний tmux.conf встановлено."

echo "ℹ️  Для застосування: вийдіть з tmux і запустіть нову сесію."
