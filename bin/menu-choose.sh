#!/bin/bash
# menu-choose.sh
#
# Опис:
# Інструмент вибору з TUI-меню
# ─────────────────────────────────────────────────────────────────────────────
# Аргументи:
#   --multi            вмикає мультивибір
#   --alt / --no-alt   вмикає/вимикає альтернативний екран
#   --header TEXT      задає заголовок; \n інтерпретується як новий рядок
#   --stdin            зчитати items зі stdin (по рядку)
#   --file FILE        зчитати items з файлу (по рядку)
#   --help             коротка довідка
#
# Повернення:
#   0    — успіх, виведено обрані рядки у stdout (по одному)
#   130  — скасовано (Ctrl+C), без виводу
#
# Sources:
#   ../lib/menu-choose/menu-choose.sh 		- функціонал для роботи з меню
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

# --- Resolve script real path even if called via symlink ---
# (під Linux достатньо readlink -f)
SCRIPT_REALPATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_REALPATH")" && pwd)"     # /usr/local/admin-scripts/bin
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                      # /usr/local/admin-scripts
LIB_DIR="$ROOT_DIR/lib"                                       # /usr/local/admin-scripts/lib

# --- Підключення бібліотек ---
source "$LIB_DIR/menu-choose/menu-choose.sh"

  SHOW_HELP=0
  CLI_MULTI=0
  CLI_ALT=""
  CLI_HEADER=""
  SRC_STDIN=0
  SRC_FILE=""
  CLI_RETURN=""     # values|indices
  CLI_INDEX_BASE="" # 0|1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) SHOW_HELP=1; shift ;;
      --multi)   CLI_MULTI=1; shift ;;
      --alt)     CLI_ALT="1"; shift ;;
      --no-alt)  CLI_ALT="0"; shift ;;
      --header)  CLI_HEADER="$2"; shift 2 ;;
      --stdin)   SRC_STDIN=1; shift ;;
      --file)    SRC_FILE="$2"; shift 2 ;;
      --indices)       CLI_RETURN="indices"; shift ;;
      --values)        CLI_RETURN="values";  shift ;;
      --index-base)    CLI_INDEX_BASE="$2";  shift 2 ;;
      --)        shift; break ;;
      -*)        echo "Невідома опція: $1" >&2; exit 2 ;;
      *)         break ;;
    esac
  done

  if (( SHOW_HELP )); then
    cat <<'HLP'
Використання:
  menu_choose.sh [--multi] [--alt|--no-alt] [--header "Текст\nще рядок"] [--stdin|--file FILE] [--] item1 item2 ...

Опції:
  --multi         дозволити мультивибір (пробіл — позначити)
  --alt|--no-alt  альтернативний екран увімк/вимк (якщо не задано — MENU_CHOOSE_ALT або 0)
  --header TEXT   заголовок (рядки можна розділити як \n)
  --stdin         зчитати пункти зі stdin (по рядку)
  --file FILE     зчитати пункти з файла (по рядку)
  --help          довідка
  --indices        повертати індекси замість значень
  --values         повертати значення (дефолт)
  --index-base N   база індексу: 0 (дефолт) або 1

Вихідні коди:
  0   успіх — вибрані рядки виведені у stdout (кожен з нового рядка)
  130 скасовано (Ctrl+C/Esc/q) — нічого не виводиться

ПРИМІТКА: передавати items як items_ref можливо лише у source-режимі:
  source menu_choose.sh
  menu_choose items=ARR outvar=OUT multi=1 altscreen=1 header=$'Привіт\nОбери:'
HLP
    exit 0
  fi

  # Зібрати items
  ITEMS=()
  if (( SRC_STDIN )); then
    mapfile -t ITEMS < <(cat)
  elif [[ -n "$SRC_FILE" ]]; then
    mapfile -t ITEMS < "$SRC_FILE"
  else
    # решта позиційних аргументів — це items
    while [[ $# -gt 0 ]]; do ITEMS+=("$1"); shift; done
  fi

  # Обробити \n у заголовку (перетворити на реальні нові рядки)
  if [[ -n "$CLI_HEADER" ]]; then
    CLI_HEADER="${CLI_HEADER//\\n/$'\n'}"
  fi

  # Підготувати вихід
  OUT=()
  # Виклик через бібліотечну функцію з іменними аргументами
  ARGS=( items=ITEMS outvar=OUT multi="$CLI_MULTI" )
  [[ -n "$CLI_HEADER" ]] && ARGS+=( header="$CLI_HEADER" )
  [[ -n "$CLI_ALT"    ]] && ARGS+=( altscreen="$CLI_ALT" )
  [[ -n "$CLI_RETURN"     ]] && ARGS+=( return="$CLI_RETURN" )
  [[ -n "$CLI_INDEX_BASE" ]] && ARGS+=( index_base="$CLI_INDEX_BASE" )

  if ! menu_choose "${ARGS[@]}"; then
    rc=$?
    # 130 — скасовано
    exit "$rc"
  fi

  # Вивід обраних (по рядку)
  printf '%s\n' "${OUT[@]}"
  exit 0
