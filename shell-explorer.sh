#!/bin/bash
# shell-explorer.sh
# Файловий провідник на Bash + fzf з діями над файлами та папками

set -euo pipefail
IFS=$'\n\t'

# ===================== COLORS =====================
NC='\033[0m'                # скидання кольору
RED='\033[91m'				# червоний
GREEN='\033[92m'			# зелений
YELLOW='\033[93m'			# жовтий
GRAY='\033[90m'             # сірий
LIGHT_GRAY='\033[38;5;247m' # світло-сірий
LIGHT_GRAY_BOLD='\033[1;38;5;247m' # жирний світло-сірий
# ===================== COLORS END =====================

log_success() { echo -e "${GREEN}✔ ${NC} $*"; }
log_warn() 	  { echo -e "${YELLOW}⚠️ ${NC} $*"; }
log_error()   { echo -e "${RED}✖ ${NC} $*"; }

# ===================== REQUIREMENTS =====================
for pkg in fzf bat; do
    if ! command -v "$pkg" &>/dev/null; then
        log_warn "Не знайдено $pkg"
        read -rp "Встановити $pkg? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            sudo apt-get update
            if [[ "$pkg" == "bat" ]]; then
                # у Debian/Ubuntu пакет називається batcat
                sudo apt-get install -y bat
                # робимо symlink на звичну назву
                if ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
                    sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
                fi
            else
                sudo apt-get install -y "$pkg"
            fi
            log_success "$pkg встановлено"
        else
			if [[ "$pkg" == "bat" ]]; then
				log_warn "Без $pkg можливості будуть обмежені"
			else
				log_error "Наявність $pkg є обов'язковим"
				exit 1
			fi
        fi
    fi
done

START_DIR="${1:-$HOME}"
CURRENT_DIR=$(realpath -m "$START_DIR")

NBSP=$'\u00A0'  # незламний пробіл

# Якщо є bat - використовуємо для перегляду
if command -v bat &>/dev/null; then
    PAGER_CMD="bat --style=numbers --paging=always --decorations=always"
else
    PAGER_CMD="less"
fi

function menu_divider(){
	echo -e "${GRAY}————————————————————————————————————${NC}"
}

function menu_header(){
	local title="$1"
    
	menu_divider
    echo -e "${LIGHT_GRAY_BOLD}$title${NC}"
    menu_divider	
}

function menu_nav_choices(){
	echo -e "${LIGHT_GRAY}c) Скасувати${NC}"
}

function menu_nav(){
	menu_divider
    menu_nav_choices
}



while true; do
	# Фікс для tmux: перший раз ширина може бути кривою
    if [[ -z "${INIT_WIDTH:-}" ]]; then
        echo -ne "⏳  Завантаження...\r"
		if [[ "${MULTIPANE:-0}" == "1" ]]; then
			sleep 0.3
		else
			sleep 0.1
		fi
        echo -ne "                     \r"  # стерти рядок
        INIT_WIDTH=1
    fi
	
	# Ширина колонки
	term_width=$(tput cols 2>/dev/null || echo 80)
	if [[ "${MULTIPANE:-0}" == "1" ]]; then
		visible_width="$term_width"
	else
		visible_width=$(( "$term_width" / 2 ))
	fi
	fixed_width=$((12 + 22 + 2))  # size + date + відступи
	name_width=$(( visible_width - fixed_width ))
	(( name_width < 20 )) && name_width=20
	
	FZF_PREVIEW='
  raw=$(printf "%s" {} | awk -F"\t" "{print \$1}")
  if [ "$raw" = "__HEADER__" ]; then
	exit 0
  fi
  if [ "$raw" = ".." ]; then
    target=$(dirname "'"$CURRENT_DIR"'")
  else
    target=$(realpath -m "'"$CURRENT_DIR"'/$raw")
  fi

  if [ -d "$target" ]; then
    shopt -s nullglob dotglob
    entries=( "$target"/* )
    shopt -u nullglob dotglob

    if [ ${#entries[@]} -eq 0 ]; then
      echo "(порожньо)"
    else
      NBSP=$'\''\u00A0'\''

      dirs=()
      files=()
      for f in "${entries[@]}"; do
        [ -e "$f" ] || continue
        if [ -d "$f" ]; then dirs+=("$f"); else files+=("$f"); fi
      done

      maxlen=1
      for f in "${dirs[@]}" "${files[@]}"; do
        name=$(basename -- "$f")
        dlen=$(( ${#name} + 1 ))
        (( dlen > maxlen )) && maxlen=$dlen
      done

      for f in "${dirs[@]}"; do
        name=$(basename -- "$f")
        display="/$name"
        info=$(stat -c "%A %U %G %5s %y" -- "$f")
        printf "%-*s  %s\n" "$maxlen" "$display" "$info"
      done
      for f in "${files[@]}"; do
        name=$(basename -- "$f")
        display="${NBSP}$name"
        info=$(stat -c "%A %U %G %5s %y" -- "$f")
        printf "%-*s  %s\n" "$maxlen" "$display" "$info"
      done
    fi
  else
    file -- "$target"
    if command -v bat &>/dev/null; then
      bat --style=plain --color=always --paging=never --line-range=:40 "$target"
    else
      head -n 40 "$target" 2>/dev/null
    fi
  fi
'

    # Збираємо імена файлів (у т.ч. прихованих)
    shopt -s nullglob dotglob
    ITEMS=( "$CURRENT_DIR"/* )
    shopt -u nullglob dotglob
	
    if [ ${#ITEMS[@]} -eq 0 ]; then
        LIST=$(
			printf "__HEADER__\t%-*.*s\t%12s\t%10s\n" \
			"$name_width" "$name_width" "Name" "Size" "Date"
			d="$CURRENT_DIR"
			name=".."
			display="/$name"
			size="<DIR>"
			mtime=$(date -r "$d" "+%Y-%m-%d %H:%M")
			printf "%s\t%-*.*s\t%12s\t%16s\n" \
			"$name" "$name_width" "$name_width" "$display" "$size" "$mtime"
		)
    else
        DIRS=()
        FILES=()
        for f in "${ITEMS[@]}"; do
          [ -e "$f" ] || continue
          if [ -d "$f" ]; then DIRS+=("$f"); else FILES+=("$f"); fi
        done
		
		# 1: raw name (службове) \t 2: display (гнучка ширина) \t 3: size \t 4: mtime
		LIST=$(
			printf "__HEADER__\t%-*.*s\t%12s\t%10s\n" \
			"$name_width" "$name_width" "Name" "Size" "Date"
			d="$CURRENT_DIR"
			name=".."
			display="/$name"
			size="<DIR>"
			mtime=$(date -r "$d" "+%Y-%m-%d %H:%M")
			printf "%s\t%-*.*s\t%12s\t%16s\n" \
			"$name" "$name_width" "$name_width" "$display" "$size" "$mtime"
			for d in "${DIRS[@]}"; do
				name=$(basename -- "$d")
				display="/$name"
				size="<DIR>"
				mtime=$(date -r "$d" "+%Y-%m-%d %H:%M")
				printf "%s\t%-*.*s\t%12s\t%16s\n" \
				"$name" "$name_width" "$name_width" "$display" "$size" "$mtime"
			done
			for f in "${FILES[@]}"; do
				name=$(basename -- "$f")
				display="${NBSP}$name"
				size=$(stat -c "%s" -- "$f" | numfmt --to=iec --suffix=B)
				mtime=$(date -r "$f" "+%Y-%m-%d %H:%M")
				printf "%s\t%-*.*s\t%12s\t%16s\n" \
				"$name" "$name_width" "$name_width" "$display" "$size" "$mtime"
			done
		)

    fi

    FZF_OPTS=(
        --multi
        --height=100%
        --reverse
        --ansi
        --prompt="📂  $CURRENT_DIR > "
        --with-nth=2,3,4
        #--layout=reverse-list
        --expect=ctrl-f,ctrl-d,ctrl-q,ctrl-o,f2,ctrl-h,f1
        --bind "home:first"
        --bind "end:last"
		--header-lines=1
    )
	
	#[[ "${MULTIPANE:-0}" == "1" ]] && FZF_OPTS+=( --border )
	[[ "${MULTIPANE:-0}" != "1" ]] && FZF_OPTS+=( --preview="$FZF_PREVIEW" )
	
    mapfile -t OUT < <(
      {
        printf '%s\n' "$LIST"
      } | fzf "${FZF_OPTS[@]}"
    ) || exit 0

    (( ${#OUT[@]} == 0 )) && continue

    KEY="${OUT[0]}"
    SEL_LINES=("${OUT[@]:1}")

    # Гарячі клавіші
    if [[ "$KEY" == "ctrl-f" ]]; then
        read -rp "Назва нового файлу: " fname
        [ -n "$fname" ] && nano "$(realpath -m "$CURRENT_DIR/$fname")"
        continue
    elif [[ "$KEY" == "ctrl-d" ]]; then
        read -rp "Назва нової папки: " dname
        if [ -n "$dname" ]; then
            mkdir -p -- "$(realpath -m "$CURRENT_DIR/$dname")"
            echo "✔ Створено папку $dname"
            read -rp "Enter..."
        fi
        continue
	elif [[ "$KEY" == "ctrl-h" || "$KEY" == "f1" ]]; then
		echo
		menu_header "⌨️  Гарячі клавіші"
		echo "↑↓ / Enter   – переміщення та вибір"
		echo "..           – піднятись на рівень вище"
		echo "Tab          – мультивибір"
		echo "F2 / Ctrl-O  – контекстне меню"
		echo "Ctrl-F       – створити новий файл"
		echo "Ctrl-D       – створити нову папку"
		echo "Ctrl-Q       – вихід"
		echo
		read -rp "Натисніть Enter, щоб повернутися..."
		continue
    elif [[ "$KEY" == "ctrl-q" ]]; then
		if [[ "${MULTIPANE:-0}" == "1" ]]; then
			# Закриваємо всю сесію tmux
			tmux kill-session -t fileman
		else
			# Звичайний вихід
			exit 0
		fi
	fi

    # Імена вибраних елементів
    SELECTED=()
	for line in "${SEL_LINES[@]}"; do
		name="${line%%$'\t'*}"
		[[ "$name" == "__HEADER__" ]] && continue
		SELECTED+=("$name")
	done
    (( ${#SELECTED[@]} == 0 )) && continue

    # Перехід на рівень вище
    if [[ "${SELECTED[0]}" == ".." ]]; then
        CURRENT_DIR=$(realpath -m "$(dirname -- "$CURRENT_DIR")")
        continue
    fi
	
	# Якщо кілька → масові дії
    if [[ ${#SELECTED[@]} -gt 1 ]]; then
		
		el_label="елементів"
		(( ${#SELECTED[@]} < 5 )) && el_label="елементи"
		
		# Контекстне меню
		echo
		menu_header "📦  ${#SELECTED[@]} $el_label"
        echo "1) Копіювати"
        echo "2) Перемістити"
		echo "3) Детальна інформація"
        echo "4) Видалити"
        menu_nav
		
        while true; do

			echo
			read -rp "Оберіть дію: " action
			
			case "$action" in
				1) read -rp "Копіювати у: " target
					for item in "${SELECTED[@]}"; do
						cp -r -i -- "$(realpath -m "$CURRENT_DIR/$item")" "$target"
					done
					echo "✔ Скопійовано у $target"; read -rp "Enter..." ;;
				2) read -rp "Перемістити у: " target
					for item in "${SELECTED[@]}"; do
						mv -i -- "$(realpath -m "$CURRENT_DIR/$item")" "$target"
					done
					echo "✔ Переміщено у $target"; read -rp "Enter..." ;;
				3) echo
					if [[ -d "$FULL_PATH" ]]; then
						ls -ldh -- "$FULL_PATH"
						stat -- "$FULL_PATH"
						echo "Вміст: $(ls -A "$FULL_PATH" | wc -l) елемент(ів)"
					else
						ls -lh -- "$FULL_PATH"
						stat -- "$FULL_PATH"
					fi
					read -rp "Enter..." ;;
				4) read -rp "Видалити вибрані елементи? [y/N]: " confirm
					[[ "$confirm" =~ ^[Yy]$ ]] && for item in "${SELECTED[@]}"; do
						rm -rf -i -- "$(realpath -m "$CURRENT_DIR/$item")"
					done && echo "✔ Видалено"
					read -rp "Enter..." ;;
				c) break ;;
				*) log_error "Некоректний вибір"; continue ;;
			esac
			
        done
		continue
    fi

    # Один файл/папка
    ITEM="${SELECTED[0]}"
    FULL_PATH=$(realpath -m "$CURRENT_DIR/$ITEM")

    if [[ -d "$FULL_PATH" ]]; then
        if [[ "$KEY" == "" ]]; then
            
			# Enter → увійти
            CURRENT_DIR="$FULL_PATH"
            continue
			
        elif [[ "$KEY" == "f2" || "$KEY" == "ctrl-o" ]]; then
            
			# Контекстне меню папки
			echo
			menu_header "📂  $FULL_PATH"
            echo "1) Створити файл"
            echo "2) Створити папку"
			echo "3) Детальна інформація"
            echo "4) Видалити"
            menu_nav
            
			while true; do
                
				echo
                read -rp "Оберіть дію: " action
                
				case "$action" in
                    1) read -rp "Назва файлу: " fname
                       [ -n "$fname" ] && nano "$(realpath -m "$FULL_PATH/$fname")" ;;
                    2) read -rp "Назва папки: " dname
                       [ -n "$dname" ] && mkdir -p "$(realpath -m "$FULL_PATH/$dname")" ;;
                    3) echo
						ls -ldh -- "$FULL_PATH"
						stat -- "$FULL_PATH"
						echo "Вміст: $(ls -A "$FULL_PATH" | wc -l) елемент(ів)"
						read -rp "Enter..." ;;
					4) read -rp "Видалити папку $FULL_PATH? [y/N]: " confirm
                       [[ "$confirm" =~ ^[Yy]$ ]] && rm -rf "$FULL_PATH" && echo "✔ Видалено"
                       read -rp "Enter..." ; break ;;
                    c) break ;;
					*) log_error "Некоректний вибір"; continue ;;
                esac
            done
        fi
    else
        if [[ "$KEY" == "" ]]; then
            
			# Enter → редагувати файл
            nano "$FULL_PATH"
			
        elif [[ "$KEY" == "f2" || "$KEY" == "ctrl-o" ]]; then
            
			# Контекстне меню файлу
			echo
            echo "📄  $FULL_PATH"
            menu_divider
            echo "1) Переглянути ($PAGER_CMD)"
            echo "2) Редагувати (nano)"
            echo "3) Детальна інформація (ls -lh)"
            echo "4) Копіювати"
            echo "5) Перемістити"
            echo "6) Видалити"
            menu_nav
				
            while true; do
                
				echo
                read -rp "Оберіть дію: " action
                
				case "$action" in
                    1) $PAGER_CMD "$FULL_PATH" ;;
                    2) nano "$FULL_PATH" ;;
                    3) echo
						ls -lh -- "$FULL_PATH"
						stat -- "$FULL_PATH"
						read -rp "Enter..." ;;
                    4) read -rp "Куди копіювати: " target
                       cp -i -- "$FULL_PATH" "$target"
                       echo "✔ Скопійовано у $target"; read -rp "Enter..." ;;
                    5) read -rp "Куди перемістити: " target
                       mv -i -- "$FULL_PATH" "$target"
                       echo "✔ Переміщено у $target"; read -rp "Enter..." ; break ;;
                    6) read -rp "Видалити файл $FULL_PATH? [y/N]: " confirm
                       [[ "$confirm" =~ ^[Yy]$ ]] && rm -i -- "$FULL_PATH" && echo "✔ Видалено"
                       read -rp "Enter..." ; break ;;
                    c) break ;;
					*) log_error "Некоректний вибір"; continue ;;
                esac
            done
        fi
    fi
done
