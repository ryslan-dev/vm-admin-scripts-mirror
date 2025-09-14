#!/bin/bash
# shell-explorers.sh
# Запускає shell-explorer.sh у двох панелях tmux (ліва/права)

# Каталоги за замовчуванням
LEFT_DIR="${1:-$HOME}"
RIGHT_DIR="${2:-$HOME}"

# Налаштування конфігурації tmux
setup-tmux &>/dev/null

# Якщо сесія fileman вже існує — вбиваємо
tmux kill-session -t fileman 2>/dev/null || true

# Запускаємо нову сесію tmux із розділеним екраном
tmux new-session -d -s fileman "MULTIPANE=1 PANE_ID=left  bash shell-explorer \"$LEFT_DIR\""
tmux split-window -h "MULTIPANE=1 PANE_ID=right bash shell-explorer \"$RIGHT_DIR\""

# Фокус одразу на лівій панелі
tmux select-pane -L

# Приєднуємося до сесії
tmux attach-session -t fileman
