#!/bin/bash

usage() {
  echo "Використання: $0 <all|username>"
  echo "  all       - вбити всі процеси vscode-server для всіх користувачів і очистити їхні тимчасові каталоги"
  echo "  username  - вбити процеси vscode-server і очистити тимчасові каталоги для конкретного користувача"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

TARGET="$1"

kill_and_cleanup_user() {
  local USERNAME="$1"
  echo "Вбиваємо процеси vscode-server для користувача $USERNAME..."
  
  pkill -u "$USERNAME" -f vscode-server
  sleep 5
  pkill -9 -u "$USERNAME" -f vscode-server

  # Шляхи для очищення
  local VS_CODE_DIRS=("$HOME/.vscode-server" "$HOME/.vscode-remote")
  
  # Якщо домашній каталог не співпадає із $HOME (для випадку root чи інших)
  local USER_HOME
  USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
  
  for dir in "${VS_CODE_DIRS[@]}"; do
    local path="${USER_HOME}/${dir##*/}"
    if [ -d "$path" ]; then
      echo "Очищаємо $path"
      rm -rf "$path"
    fi
  done

  echo "Готово для користувача $USERNAME."
}

if [ "$TARGET" == "all" ]; then
  echo "Вбиваємо процеси vscode-server для всіх користувачів..."

  pkill -f vscode-server
  sleep 5
  pkill -9 -f vscode-server

  echo "Очищаємо тимчасові каталоги vscode-server для всіх користувачів..."

  for dir in /home/*; do
    if [ -d "$dir" ]; then
      echo "Очищаємо $dir/.vscode-server та $dir/.vscode-remote"
      rm -rf "$dir/.vscode-server" "$dir/.vscode-remote"
    fi
  done

  # Для root
  if [ -d "/root/.vscode-server" ]; then
    echo "Очищаємо /root/.vscode-server та /root/.vscode-remote"
    rm -rf /root/.vscode-server /root/.vscode-remote
  fi

  echo "Готово для всіх користувачів."

else
  # Перевірка чи існує користувач
  if id "$TARGET" &>/dev/null; then
    kill_and_cleanup_user "$TARGET"
  else
    echo "Користувач '$TARGET' не знайдений."
    exit 1
  fi
fi
