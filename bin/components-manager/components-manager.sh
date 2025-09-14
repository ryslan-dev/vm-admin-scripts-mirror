#!/bin/bash

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
IFS=$'\n\t'

# Source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/components-data"
source "$SCRIPT_DIR/menu-choose"

# 🛑 Root перевірка
if [[ "$EUID" -ne 0 ]]; then
  log_error "Для роботи скрипта потрібні права root"
  exit 1
fi

# ===================== VARIABLES =====================

TYPE=""
SELECT=()
FILTER=()
SEARCH=""
COMPONENTS=()
SELECTED_COMPONENTS=()

# ===================== MENU CHOOSE TYPE =====================

MENU_CHOOSE_TYPE=""
MENU_CHOOSE_TYPE="menu_choose"
#MENU_CHOOSE_TYPE="whiptail"
#MENU_CHOOSE_TYPE="dialog"
#if [[ -z "$MENU_CHOOSE_TYPE" ]] && check_gum_install; then
#	MENU_CHOOSE_TYPE="gum"
#fi

# ===================== FUNCTIONS =====================

function array_isset() {
    declare -p "$1" 2>/dev/null | grep -q 'declare \-\(a\|A\)'
}

function is_assoc_array() {
	declare -p "$1" 2>/dev/null | grep -q 'declare \-A'
}

function is_array_single() {
    local -n _arr="$1"
    [[ "${#_arr[@]}" -eq 1 ]]
}

function is_array_empty() {
    local -n _arr="$1"
    [[ ${#_arr[@]} -eq 0 ]]
}

function in_array() {
    local v="$1"
    local -n _arr="$2"
    local e
    for e in "${_arr[@]}"; do
        [[ "$e" == "$v" ]] && return 0
    done
    return 1
}

function array_has_key() {
    local key="$1"
	local arr_name="$2"

    # Перевірка, що змінна існує
    local decl
    decl=$(declare -p "$arr_name" 2>/dev/null) || return 1

    # Перевірка, що змінна — масив (індексований або асоціативний)
    if [[ $decl =~ "declare -a" || $decl =~ "declare -A" ]]; then
        # Використовуємо [[ -v ]] для безпечної перевірки ключа
        [[ -v "${arr_name}[$key]" ]]
    else
        return 1
    fi
}

function array_key_has_value() {
    local key="$1"
	local arr_name="$2"

    # Чи існує масив?
    local decl
    decl=$(declare -p "$arr_name" 2>/dev/null) || return 1
    [[ $decl =~ "declare -a" || $decl =~ "declare -A" ]] || return 1

    # Чи існує ключ і чи значення не порожнє?
    if [[ -v "${arr_name}[$key]" && -n "${arr_name}[$key]" ]]; then
        return 0
    else
        return 1
    fi
}

function array_key_get() {
    local arr_name="$1"
    local key="$2"
    local default="${3:-}"  # якщо не передали, буде ""

    # Перевірка існування і що це масив
    local decl
    decl=$(declare -p "$arr_name" 2>/dev/null) || { echo "$default"; return 1; }
    [[ $decl =~ "declare -a" || $decl =~ "declare -A" ]] || { echo "$default"; return 1; }

    # Nameref для доступу до масиву
    local -n ref="$arr_name"

    if [[ -v "ref[$key]" ]]; then
        echo "${ref[$key]}"
        return 0
    else
        echo "$default"
        return 1
    fi
}

function array_get() {
    local arr_name="$1"
    local key="$2"
    local default="${3:-}"  # якщо не передали – порожній рядок

    # Перевірка, що масив існує і це дійсно масив
    local decl
    decl=$(declare -p "$arr_name" 2>/dev/null) || { echo "$default"; return 1; }
    [[ $decl =~ "declare -a" || $decl =~ "declare -A" ]] || { echo "$default"; return 1; }

    # Nameref для доступу
    local -n ref="$arr_name"

    if [[ -v "ref[$key]" && -n "${ref[$key]}" ]]; then
        echo "${ref[$key]}"
        return 0
    else
        echo "$default"
        return 1
    fi
}

# get_array_key "значення" масив_асоціативний
# Повертає ключ, якщо знайдений
function get_array_key() {
    local value="$1"
    local -n assoc="$2"
    local key
    for key in "${!assoc[@]}"; do
        if [[ "${assoc[$key]}" == "$value" ]]; then
            echo "$key"
            return 0
        fi
    done
    return 1
}

function function_isset() {
	type "$1" &>/dev/null
}

# Drop-in: підтримує \n та багаторядкові статуси і зносить увесь блок
function status_do() {
  local msg="$1"; shift
  exec 9>/dev/tty || return 1

  # Інтерпретуємо \n, \t, \e тощо
  local _msg
  printf -v _msg '%b' "$msg"

  # Скільки «логічних» рядків надрукуємо (включно з порожнім після трейлінгового \n)
  local _nl_removed="${_msg//$'\n'/}"
  local _nl_cnt=$(( ${#_msg} - ${#_nl_removed} ))
  local _lines=0
  [[ -n $_msg ]] && _lines=$(( _nl_cnt + 1 ))  # "abc" -> 1; "a\nb\n" -> 3

  # Зберегти позицію і сховати курсор
  tput sc >&9
  tput civis >&9

  # Намалювати статус (без \n в кінці — виводимо як є)
  if (( _lines > 0 )); then
    printf '%s' "$_msg" >&9
  fi

  # Cleanup: повертаємось у якір та видаляємо рівно наш блок
  status_do_cleanup() {
    tput rc >&9
    if (( _lines > 0 )); then
      if tput dl1 >/dev/null 2>&1; then
        local i; for ((i=0; i<_lines; i++)); do tput dl1 >&9; done
      else
        printf '\033[%dM' "$_lines" >&9
      fi
    fi
    tput cnorm >&9
    exec 9>&-
    trap - INT TERM EXIT
  }
  trap status_do_cleanup INT TERM EXIT

  # Запустити дію тихо
  "$@" >/dev/null 2>&1
  local rc=$?

  status_do_cleanup
  return "$rc"
}

function is_required() {
  local name="$1"
  local value="$2"
  [[ "$value" == "required" ]] && return 0
  [[ "${COMPONENT_PRIORITIES[$value]:-}" == "required" ]] && return 0
  
  return 1
}

function check_required() {
  local name="$1"
  local value="$2"
  [[ "$value" == "required" ]] && {
    log_warn "$name є обов'язковим для роботи системи"
    return 1
  }
  return 0
}

function is_required_dir() {
    [[ "$1" =~ ^(/|/bin|/dev|/var|/var/backups|/var/mail|/run/sshd|/var/www)$ ]]
}

function search_string() {
  local value="$1"
  local pattern="$2"
  
  # Переводимо обидва рядки у нижній регістр
  value="${value,,}"
  pattern="${pattern,,}"
  
  if [[ "$value" == *"$pattern"* ]]; then
    return 0
  else
    return 1
  fi
}

function components_list() {
  local -n arr=$1
  local count=${#arr[@]}
  
  # визначаємо ширину для індексу
  local width=${#count}  # кількість цифр у числі count
  
  local index=1
  for name in "${arr[@]}"; do
  
	printf "%-${width}s %s\n" "$index" "$name"
	((index++))
  done
  echo
}

function get_label() {
    local key="$1"
    local type_labels="${TYPE}_labels"
    local template=""

    # Пошук у TYPE-специфічному масиві
    if declare -p "$type_labels" &>/dev/null; then
        template="$(eval "echo \${$type_labels[$key]:-}")"
    fi

    # Якщо нема у TYPE-специфічному, беремо з глобального
    if [[ -z "$template" ]]; then
        template="${LABELS[$key]:-}"
    fi

    # Якщо нічого не знайдено
    [[ -z "$template" ]] && return 1

    # Підстановка змінних з шаблону
    eval "echo \"$template\""
}

function choose_items() {
	local input="$1"
	local -n Items="$2"
	local -n _out=$3
	_out=()
  
	local Selected_items=()
	local -A Already_selected

	IFS=',' read -ra parts <<< "$input"

    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^[0-9]+$ ]]; then
            # Одиночне число
            idx=$part
            if (( idx >= 1 && idx <= ${#Items[@]} )); then
			  item="${Items[$((idx-1))]}"
			  if [[ -z "${Already_selected[$item]+_}" ]]; then
				  Selected_items+=("$item")
				  Already_selected[$item]=1
			  fi
            else
              log_error "Некоректний номер: $idx"
            fi
        elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # Діапазон
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}
            if (( start > end )); then
                log_error "Некоректний діапазон: $part (початок більший за кінець)"
                continue
            fi
            if (( start < 1 || end > ${#Items[@]} )); then
                log_error "Діапазон поза межами: $part"
                continue
            fi
            for (( idx=start; idx<=end; idx++ )); do
			  item="${Items[$((idx-1))]}"
			  if [[ -z "${Already_selected[$item]+_}" ]]; then
				Selected_items+=("$item")
				Already_selected[$item]=1
			  fi
            done
        else
            log_error "Некоректний формат вводу: $part"
        fi
    done
	
	_out=("${Selected_items[@]}")
}

function available_shells_list(){

	local AVAILABLE_SHELLS
	readarray -t AVAILABLE_SHELLS < <(grep -vE '^\s*#' /etc/shells)
	
	components_list AVAILABLE_SHELLS
}

function show_available_shells_list(){
	
	echo -e "${BOLD}Доступні Shells для входу:${NC}\n"
	available_shells_list
}

# ===================== MENU =====================

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
	echo -e "${LIGHT_GRAY}x) Вийти${NC}"
}

function menu_nav(){
	#menu_header "Навігація меню:"
	menu_divider
    menu_nav_choices
}

# menu_gum outvar=RESULT options=MY_ARRAY header="Заголовок" cursor="" multi=1
function menu_gum() {
    local outvar="" cursor="" header="" multi=0 height=""
    local -n _items

    # Розбір іменованих аргументів
    for arg in "$@"; do
        case $arg in
            outvar=*) outvar="${arg#*=}" ;;
            cursor=*) cursor="${arg#*=}" ;;
            header=*) header="${arg#*=}" ;;
            multi=*)  multi="${arg#*=}" ;;
			height=*)  height="${arg#*=}" ;;
			items|options=*) local arrname="${arg#*=}"; _items="$arrname" ;;
         esac
    done

    [[ -z "$outvar" ]] && { log_error "menu_gum: потрібен аргумент outvar="; return 1; }
    [[ -z "$_items" ]] && { log_error "menu_gum: потрібен аргумент items="; return 1; }

    local gum_opts=(
        --cursor="$cursor"
        --header="$header"
    )
	
	# висота (кількість рядків на екран)
	if [[ -z "$height" ]]; then
		height="${#_items[@]}"
	fi
	gum_opts+=( --height="$height" )
	
	# мультивибір
    if [[ "$multi" == "1" ]]; then
        gum_opts+=( --no-limit )
    fi

    # Запуск gum choose
    local result clean_result
    result=$(printf "%s\n" "${_items[@]}" | gum choose "${gum_opts[@]}")
	clean_result="$(printf '%s\n' "$result" | sed '/^[[:space:]]*$/d')"
	
    if [[ "$multi" == "1" ]]; then
        # Мультивибір → масив
		if [[ -z "$clean_result" ]]; then
			local -n _Out="$outvar"
			_Out=()
		else
			readarray -t "$outvar" <<< "$result"
		fi
    else
        # Один вибір → звичайна змінна
		if [[ -z "$clean_result" ]]; then
			result=""
		fi
        printf -v "$outvar" "%s" "$result"
    fi
}

# menu_fzf outvar=RESULT options=MY_ARRAY header="Заголовок" cursor=">" multi=1
function menu_fzf() {
  local outvar="" cursor=">" header="" multi=0 search=0 prompt="" height="" border=0
  local -n _items

  for arg in "$@"; do
    case $arg in
      outvar=*) outvar="${arg#*=}" ;;
      cursor=*) cursor="${arg#*=}" ;;
      header=*) header="${arg#*=}" ;;
      multi=*)  multi="${arg#*=}" ;;
      search=*) search="${arg#*=}" ;;
      prompt=*) prompt="${arg#*=}" ;;
	  border=*) border="${arg#*=}" ;;
	  height=*) height="${arg#*=}" ;;
      items|options=*) local arrname="${arg#*=}"; _items="$arrname" ;;
    esac
  done

  [[ -z "$outvar" ]] && { log_error "menu_fzf: потрібен outvar="; return 1; }
  [[ -z "$_items" ]] && { log_error "menu_fzf: потрібен items="; return 1; }

  # Опції fzf
  local fzf_opts=( --ansi --no-info --cycle --reverse )
  
  # заголовок
  [[ -n "$header" ]] && fzf_opts+=( --header="$header" )
  
  # курсор
  [[ -n "$cursor" ]] && fzf_opts+=( --pointer="$cursor" )
  
  # мультивибір
  (( multi )) && fzf_opts+=( --multi --marker="✔" )
  
  # пошук
  (( search == 0 )) && fzf_opts+=( --disabled --bind "change:clear-query" )
  
  # prompt
  fzf_opts+=( --prompt="$prompt" )
  
  # контур
  (( border )) && fzf_opts+=( --border )
  
  # висота
  [[ -n "$height" ]] && fzf_opts+=( --height="$height" )

  local selection
  selection=$(printf "%s\n" "${_items[@]}" | fzf "${fzf_opts[@]}")

  if [[ "$multi" == "1" ]]; then
    readarray -t "$outvar" <<< "$selection"
  else
    printf -v "$outvar" "%s" "$selection"
  fi
}

function component_menu_choose(){
	local items="" labels="" header="" outvar="" multi=0 allow_null=""
	
	for arg in "$@"; do
        case "$arg" in
            items=*) items="${arg#*=}" ;;
			labels=*) labels="${arg#*=}" ;;
			multi=*) multi="${arg#*=}" ;;
			allow_null=*) allow_null="${arg#*=}" ;;
            header=*) header="${arg#*=}" ;;
			outvar=*) outvar="${arg#*=}" ;;
        esac
    done
	
	[[ -z "${outvar:-}" ]] && { log_error "component_menu_choose: потрібен аргумент outvar="; return 1; }
	[[ -z "${items:-}" ]] && { log_error "component_menu_choose: потрібен аргумент items="; return 1; }
	[[ -z "${labels:-}" ]] && { log_error "component_menu_choose: потрібен аргумент labels="; return 1; }
    
	local -n Items="$items"
	local -n Labels="$labels"
	
	[[ ${#Items[@]} -eq 0 ]] && { log_error "component_menu_choose: елементів меню не знайдено"; return 1; }
	[[ ${#Labels[@]} -eq 0 ]] && { log_error "component_menu_choose: заголовків меню не знайдено"; return 1; }
	
	# menu list
	local Menu_items=()
	local TAB=$'\t'
	for key in "${Items[@]}"; do
		Menu_items+=("${key}${TAB}${Labels[$key]:-$key}")
	done
	
	local Actions=("ok" "cancel" "exit")
	local -A Action_labels=(
		[ok]="OK"
		[cancel]="Скасувати"
		[exit]="Вийти"
	)
	local Menu_actions=()
	for key in "${Actions[@]}"; do
		Menu_actions+=("${Action_labels[$key]:-$key}")
	done
	
	local Menu_header=""
	[[ -n "$header" ]] && Menu_header="$(menu_header "$header")"
	
	while true; do
		
		local MenuResult=""
		local MenuAact=""
		
		menu_choose \
		header="$Menu_header" \
		items=Menu_items item_retcol=1 \
		multi="$multi"  \
		allow_null="$allow_null" \
		outvar=MenuResult \
		actions_ref=Menu_actions actionvar=MenuAact
		
		rc=$?
		
		if [[ -n "$MenuAact" ]]; then
			MenuAact=$(get_array_key "$MenuAact" Action_labels)
		fi
		
		if [[ $rc -gt 0 ]]; then
			[[ "$rc" == "${MENU_CHOOSE_EXIT_RC:-3}" ]] && exit 0
			[[ "$rc" == "${MENU_CHOOSE_ABORT_RC:-130}" ]] && exit 0
			return "$rc"
		else
			case "$MenuAact" in
				cancel) return "${MENU_CHOOSE_CANCEL_RC:-2}" ;;
				exit) exit 0 ;;
			esac
		fi
		
		local -n _OUT="$outvar"
		local choices=() choice
		
		if (( multi ));then
		
			_OUT=()
			
			if array_isset "MenuResult"; then
				[[ ${#MenuResult[@]} -gt 0 ]] && choices=("${MenuResult[@]}")
			else
				[[ -n "$MenuResult" ]] && choices=("$MenuResult")
			fi
			
			if [[ ${#choices[@]} -gt 0 ]]; then
				for key in "${choices[@]}"; do
		    
					choice="$key"
					#choice=$(get_array_key "$key" Labels)
					
					[[ -z "$choice" ]] && {
						log_error "Некоректний вибір"
						return 1
					}
		  
					case "$choice" in
						c|cancel) return 1 ;;
						x|exit) exit 0 ;;
						*) _OUT+=("$choice"); break ;;
					esac
			
				done
			fi
			
		else
			
			_OUT=""
			
			choice="$MenuResult"
			#choice=$(get_array_key "$MenuResult" Labels)
			
			[[ -z "$choice" ]] && {
				log_error "Некоректний вибір"
				return 1
			}
		  
			case "$choice" in
			  c|cancel) return 1 ;;
			  x|exit) exit 0 ;;
			  *) 
				if array_isset "${choice}_items"; then
				
					local Sub_items
					local Sub_header
					
					local -n _Opts="${choice}_items"
					Sub_items=("${_Opts[@]}")
					
					if [[ -n "${Labels[${choice}_header]:-}" ]]; then
						Sub_header="${Labels[${choice}_header]}"
					elif [[ -n "${Labels[${choice}]:-}" ]]; then
						Sub_header="${Labels[${choice}]}"
					else
						Sub_header="$choice"
					fi
					
					while true; do
					
						component_menu_choose items=Sub_items labels="$labels" outvar="$outvar" multi="$multi" allow_null="$allow_null" header="$Sub_header"
						rc=$?
					
						if [[ $rc -gt 0 ]]; then
							[[ "$rc" == "${MENU_CHOOSE_CANCEL_RC:-2}" ]] && continue 2
						fi
						
						break
					done
					
				else
					_OUT="$choice"
				fi
				;;
			esac
			
			component_action
			rc=$?
			if [[ $rc -gt 0 ]]; then
				[[ "$rc" == "${MENU_CHOOSE_CANCEL_RC:-2}" ]] && continue
			fi

		fi
		
		break
	done
}

function component_menu_gum(){
	local -n _opts="$1"
	local -n _labels="$2"
	local header="" outvar="" multi=0 choices choice selected
	
	for arg in "$@"; do
        case "$arg" in
            multi=*) multi="${arg#*=}" ;;
            header=*) header="${arg#*=}" ;;
			outvar=*) outvar="${arg#*=}" ;;
        esac
    done
	
	[[ -z "$outvar" ]] && { log_error "component_menu_gum: потрібен аргумент outvar="; return 1; }
    [[ -z "$_opts" ]] && { log_error "component_menu_gum: не знайдено дані 'items'"; return 1; }
	[[ -z "$_labels" ]] && { log_error "component_menu_gum: не знайдено дані 'labels'"; return 1; }
	
	local _options=("${_opts[@]}")
	
	_options+=("c")
	_options+=("x")
	
	# menu list
	local Options=()
	local i=1
	for key in "${_options[@]}"; do
		Options+=("${_labels[$key]:-$key}")
		((i++))
	done

	while true; do
		
		selected=""
		
		# menu
		menu_gum header="$header" options=Options multi="$multi" outvar=selected

		# Якщо нічого не вибрано (натиснули Esc або Ctrl+C)
		if ! array_isset "selected" && [[ -z "$selected" ]]; then
			exit 0
		elif array_isset "selected" && [[ ${#selected[@]} -eq 0 ]]; then
			
			log_error "Нічого не вибрано. Для вибору натисніть пробіл. Ctrl+A - обрати усі"
			
			# Питаємо чи продовжити вибір
			local ans ans_opts
			local ans_options=()
			
			local -A ans_labels=(
				[choose]="Продовжити обирати"
				[cancel]="Скасувати"
				[exit]="Вийти"
			)
			
			ans_opts=(
				choose
				cancel
				exit
			)
			
			for key in "${ans_opts[@]}"; do
				ans_options+=("${ans_labels[$key]:-$key}")
			done
			
			menu_gum options=ans_options multi=0 outvar=ans
			ans=$(get_array_key "$ans" ans_labels)
			
			case "$ans" in
				cancel) return 1 ;;
				exit) exit 0 ;;
				*) continue ;;
			esac
		fi
		
		choices=()
		if array_isset "selected"; then
			[[ ${#selected[@]} -gt 0 ]] && choices=("${selected[@]}")
		else
			[[ -n "$selected" ]] && choices=("$selected")
		fi
		
		local -n _OUT="$outvar"
		
		if [[ "$multi" == "1" ]]; then
			_OUT=()
		else
			_OUT=""
		fi
		
		if [[ ${#choices[@]} -gt 0 ]]; then
		
		  for key in "${choices[@]}"; do

		    choice=$(get_array_key "$key" _labels)
		  
			[[ -z "$choice" ]] && {
				log_error "Некоректний вибір"
				return 1
			}
		  
			case "$choice" in
			  c|cancel) return 1 ;;
			  x|exit) exit 0 ;;
			  *) 
				if array_isset "${choice}_items"; then
					
					local _menu_header
					local n _menu_labels="$_labels"
					local -n _opts="${choice}_items"
					
					local _menu_options=("${_opts[@]}")
					
					if [[ -n "${_labels[${choice}_header]:-}" ]]; then
						_menu_header="${_labels[${choice}_header]}"
					elif [[ -n "${_labels[${choice}]:-}" ]]; then
						_menu_header="${_labels[${choice}]}"
					else
						_menu_header="$choice"
					fi
				
					component_menu_gum _menu_options _menu_labels outvar="$outvar" multi="$multi" header="$(menu_header "$_menu_header")"
					rc=$?

					if [[ $rc -eq 2 ]]; then
						continue # invalid
					elif [[ $rc -eq 1 ]]; then
						return 1
					fi
				
				else
					if [[ "$multi" == "1" ]]; then
						_OUT+=("$choice")
					else
						_OUT="$choice"
						break
					fi
				fi
				;;
			esac
		  done
		
		fi
		
		break
	done
	
	return 0
}

function choose_type_menu() {

	# menu choose
	if [[ "$MENU_CHOOSE_TYPE" == "menu_choose" ]]; then
	
		local items
		local -A labels
		
		items=("${TYPES[@]}")
		items+=("exit")
	
		labels=(
			[exit]='🚪  Вийти'
		)

		for key in "${TYPES[@]}"; do
			labels["$key"]="${HEADER_LABELS[$key]:-$key}"
		done
	
		# Побудова списку для gum: "Назва [ключ]"
		local menu_items=()
		for key in "${items[@]}"; do
			menu_items+=( "${labels[$key]:-$key}" )
		done

		# Виклик gum choose
		local choice
		while true; do
			
			choice=""
			
			menu_choose header="$(menu_header "🧩  Виберіть")" items=menu_items outvar=choice multi=0 allow_null=0
			
			# Якщо нічого не вибрано (натиснули Esc або Ctrl+C)
			[[ -z "$choice" ]] && exit 0

			choice=$(get_array_key "$choice" labels)
	
			[[ -z "$choice" ]] && { 
				log_error "Некоректний вибір"
				continue 
			}
	
			if in_array "$choice" TYPES; then
				TYPE="$choice"
				break
			fi
	
			if [[ "$choice" == "exit" ]]; then
				exit 0
			fi
			
			break
		done
	
	# menu gum
	elif [[ "$MENU_CHOOSE_TYPE" == "gum" ]]; then
		
		local items
		local -A labels
		
		items=("${TYPES[@]}")
		items+=("exit")
	
		labels=(
			[exit]='🚪  Вийти'
		)

		for key in "${TYPES[@]}"; do
			labels["$key"]="${HEADER_LABELS[$key]:-$key}"
		done
	
		# Побудова списку для gum: "Назва [ключ]"
		local options=()
		for key in "${items[@]}"; do
			options+=( "${labels[$key]:-$key}" )
		done

		# Виклик gum choose
		local choice
		while true; do
	
			menu_gum header="$(menu_header "🧩  Виберіть")" options=options multi=0 outvar=choice

			# Якщо нічого не вибрано (натиснули Esc або Ctrl+C)
			[[ -z "$choice" ]] && exit 0
	
			choice=$(get_array_key "$choice" labels)
	
			[[ -z "$choice" ]] && { 
				log_error "Некоректний вибір"
				continue 
			}
	
			if in_array "$choice" TYPES; then
				TYPE="$choice"
				break
			fi
	
			if [[ "$choice" == "exit" ]]; then
				exit 0
			fi
	
		done
	
	else
	
	# menu read
	menu_header "🧩  Виберіть:"
		
	local index=1
	for key in "${TYPES[@]}"; do
		echo -e "${BOLD} $index) ${HEADER_LABELS[$key]:-$key}${NC}"
		((index++))
	done
		
	menu_divider
	echo -e "${LIGHT_GRAY}x) Вийти${NC}"
    
	while true; do

		echo    
		read -rp "> " choice
	
		if [[ -z "$choice" ]]; then
			log_error "Нічого не вибрано"
			continue
		elif [[ "$choice" == "x" ]]; then
			exit 0
		elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#TYPES[@]} )); then
			TYPE="${TYPES[$((choice-1))]}"
			break
		else
			log_error "Некоректний вибір"
			continue
		fi
	done
	
	fi
}

function component_select_menu(){

	local -A select_menu_labels=()
	local select_menu_items=()

	if function_isset "${TYPE}_select_menu_items"; then
	
		"${TYPE}_select_menu_items" select_menu_items select_menu_labels
	fi

	if ! array_isset "select_menu_items"; then
		log_error "Дані 'select_menu_items' для меню '$Header' не знайдено"
		return 1
	fi
	if ! array_isset "select_menu_labels"; then
		log_error "Дані 'select_menu_labels' для меню '$Header' не знайдено"
		return 1
	fi
	
	local Header
	if array_key_has_value "${TYPE}_menu_header" select_menu_labels; then
		Header="${select_menu_labels[${TYPE}_menu_header]}"
	elif array_key_has_value "$TYPE" HEADER_LABELS; then
		Header="${HEADER_LABELS[$TYPE]}"
	else
		Header="$TYPE"
	fi
	
	if [[ "$MENU_CHOOSE_TYPE" == "menu_choose" ]]; then
		
		SELECT=()

		component_menu_choose items=select_menu_items labels=select_menu_labels outvar=SELECT multi=0 allow_null=0 header="$Header"
		
	else
	
	  # Список меню
	  local -A keys=()
	  local -A indexes=()
	  local i=1
	  for key in "${select_menu_items[@]}"; do
		if [[ "$key" == "menu_devider" ]]; then
			menu_divider
		elif [[ "$key" == "menu_nav" ]]; then
			menu_nav
		elif in_array "$key" menu_parts; then
			menu_header "${select_menu_labels[${key}_header]:-$key}"
		else
			echo -e "$i) ${select_menu_labels[$key]:-$key}"
			keys["$i"]="$key"
			indexes["$key"]="$i"
			((i++))
		fi
	  done
    
	  local choices choice
	  local prev_input=""
	
	  while true; do
		
		echo
		# показуємо попереднє введення, якщо є
		read -re -i "$prev_input" -p "> " input
		
		# Розділяємо введене значення по комах або пробілах
		IFS=', ' read -ra choices <<< "$input"
		# прибирає пусті
		filtered_choices=()
		for c in "${choices[@]}"; do
			[[ -n "$c" ]] && filtered_choices+=("$c")
		done
		choices=("${filtered_choices[@]}")
		
		if [[ ${#choices[@]} -eq 0 ]]; then
			log_error "Нічого не вибрано"
			prev_input="$input"
            continue # invalid
		fi
		
		SELECT=()
		
		# Парсинг вибору
		for choice in "${choices[@]}"; do
			case "$choice" in
				c|cancel) return 1 ;;
				x|exit) exit 0 ;;
				*)
				  if [[ -n "$choice" && -n "${keys[$choice]:-}" ]]; then
					SELECT+=("${keys[$choice]}")
				  elif [[ -n "$choice" ]]; then
					log_error "Некоректний вибір"
					prev_input="$input"
					continue # invalid
				  fi
				  ;;
			esac
		done
		
		if [[ ${#SELECT[@]} -eq 0 ]]; then
			log_error "Нічого не вибрано"
			prev_input="$input"
            continue # invalid
		fi

        break
	  done
	
	fi
}

function component_filter_menu() {

	local -A filter_menu_labels=()
	local filter_menu_items=()
	
	if function_isset "${TYPE}_filter_menu_items"; then
	
		"${TYPE}_filter_menu_items" filter_menu_items filter_menu_labels
	fi

	local Header
	if array_key_has_value "${TYPE}_menu_header" filter_menu_labels; then
		Header="${filter_menu_labels[${TYPE}_menu_header]}"
	elif array_key_has_value "$TYPE" HEADER_LABELS; then
		Header="${HEADER_LABELS[$TYPE]}"
	else
		Header="$TYPE"
	fi

	# menu choose
	if [[ "$MENU_CHOOSE_TYPE" == "menu_choose" ]] && ! is_array_empty "filter_menu_items" && ! is_array_empty "filter_menu_labels"; then
		
		FILTER=()
		SEARCH=""

		component_menu_choose items=filter_menu_items labels=filter_menu_labels outvar=FILTER multi=1 allow_null=1 header="$Header"
		rc=$?

		if [[ $rc -gt 0 ]]; then
			return "$rc"
		fi

		# якщо вибрано "search" — питаємо рядок для пошуку
		if in_array "search" FILTER; then
			while true; do
				echo
				read -rp "Введіть ключові символи для пошуку: " SEARCH
				if [[ -z $SEARCH ]]; then
					log_error "Рядок пошуку не може бути порожнім"
					continue
				fi
				break
			done
        fi
		
		return "$rc"
	
	# menu gum
	elif [[ "$MENU_CHOOSE_TYPE" == "gum" ]] && ! is_array_empty "filter_menu_items" && ! is_array_empty "filter_menu_labels"; then
		
		FILTER=()
		SEARCH=""

		component_menu_gum filter_menu_items filter_menu_labels outvar=FILTER multi=1 header="$Header"
        rc=$?

		if [[ $rc -eq 2 ]]; then
			return 2
		elif [[ $rc -eq 1 ]]; then
			return 1
		fi

		# якщо вибрано "search" — питаємо рядок для пошуку
		if in_array "search" FILTER; then
			while true; do
				echo
				read -rp "Введіть ключові символи для пошуку: " SEARCH
				if [[ -z $SEARCH ]]; then
					log_error "Рядок пошуку не може бути порожнім"
					continue
				fi
				break
			done
        fi

	else
	
	  # Список меню
	  if ! is_array_empty "filter_menu_items" && ! is_array_empty "filter_menu_labels"; then
		
		filter_menu_items+=("menu_nav")
		
		if ! in_array "menu_header" filter_menu_items; then
			menu_header "$Header"
		fi
		
		local -A keys=()
		local -A indexes=()
		local i=1
		for key in "${filter_menu_items[@]}"; do
			if [[ "$key" == "menu_devider" ]]; then
				menu_divider
			elif [[ "$key" == "menu_header" ]]; then
				menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}"
			elif [[ "$key" == "menu_nav" ]]; then
				menu_nav
			elif array_isset "menu_parts" && in_array "$key" menu_parts; then
				menu_header "${filter_menu_labels[${key}_header]:-$key}"
			elif [[ "$key" == "all" ]]; then
				echo -e "${filter_menu_labels[$key]:-$key}"
				keys[all]="$key"
				indexes["$key"]=all
			elif [[ "$key" == "search" ]]; then
				echo -e "s) ${filter_menu_labels[$key]:-$key}"
				keys[s]="$key"
				indexes["$key"]=s
			else
				echo -e "$i) ${filter_menu_labels[$key]:-$key}"
				keys["$i"]="$key"
				indexes["$key"]="$i"
				((i++))
			fi
		done
		
	  elif function_isset "show_${TYPE}_filter_menu" && function_isset "parse_${TYPE}_filter_choices"; then

		# Виклик відображення меню з відповідного модуля
		"show_${TYPE}_filter_menu"
	
	  else
		log_error "Меню для '$Header' не знайдено"
		return 1
	  fi
	
	  local choices choice
	  local prev_input=""
      while true; do
		
		echo
		# показуємо попереднє введення, якщо є
		read -re -i "$prev_input" -p "> " input
		
		# Розділяємо введене значення по комах або пробілах
		IFS=', ' read -ra choices <<< "$input"
		# прибирає пусті
		filtered_choices=()
		for c in "${choices[@]}"; do
			[[ -n "$c" ]] && filtered_choices+=("$c")
		done
		choices=("${filtered_choices[@]}")

		FILTER=()
		SEARCH=""
		
		# Парсинг вибору
		if array_isset "filter_menu_items" && array_isset "filter_menu_labels"; then
		
			for choice in "${choices[@]}"; do
			  case "$choice" in
				c) return 1 ;;
				x) exit 0 ;;
				*)
				  if [[ -n "$choice" && -n "${keys[$choice]:-}" ]]; then
					FILTER+=("${keys[$choice]}")
				  elif [[ -n "$choice" ]]; then
					log_error "Некоректний вибір"
					prev_input="$input"
					continue # invalid
				  fi
				  ;;
			  esac
			done
		
		elif function_isset "show_${TYPE}_filter_menu" && function_isset "parse_${TYPE}_filter_choices"; then
			
			# Парсинг вибору з відповідного модуля
			"parse_${TYPE}_filter_choices"
			rc=$?

			if [[ $rc -eq 2 ]]; then
				prev_input="$input"
				continue # invalid
			elif [[ $rc -eq 1 ]]; then
				return 1
			fi
		else
			log_error "Меню для '$Header' не знайдено"
			return 1
		fi
		
		# якщо вибрано "search" — питаємо рядок для пошуку
		if in_array "search" FILTER; then
            echo
			read -rp "Введіть ключові символи для пошуку: " SEARCH
            if [[ -z $SEARCH ]]; then
                log_error "Рядок пошуку не може бути порожнім"
				prev_input="$input"
                continue
            fi
        fi
		
        break
	  done
	
	fi
}

function search_components() {
	
	COMPONENTS=()
	#echo -e "\n🔎  $(get_label get_components)...\n"
	#"get_${TYPE}_components" FILTER COMPONENTS
	
	status_do "\n🔎  $(get_label get_components)..." "get_${TYPE}_components" FILTER COMPONENTS
	
	if is_array_empty COMPONENTS; then
		if is_array_empty FILTER; then
		  log_warn "$(get_label no_components_found)"
		else
		  log_warn "$(get_label no_components_found_with_filter)"
		fi
		return 1
	fi
}

function component_list_menu() {
	
	# menu choose
	if [[ "$MENU_CHOOSE_TYPE" == "menu_choose" ]]; then
	
		while true; do
	
			local Header
			if is_array_single COMPONENTS; then
				Header="${BLUE_BOLD}🟦  $(get_label available_component):${NC}"$'\n'
			else
				Header="${BLUE_BOLD}🟦  $(get_label available_components):${NC}"$'\n'
			fi
	
			local Actions=("ok" "cancel" "exit")
			local -A Action_labels=(
				[ok]="OK"
				[cancel]="Скасувати"
				[exit]="Вийти"
			)
			local Menu_actions=()
			for key in "${Actions[@]}"; do
				Menu_actions+=("${Action_labels[$key]:-$key}")
			done
		
			local MenuAact=""
		
			menu_choose header="$Header" items=COMPONENTS outvar=SELECTED_COMPONENTS multi=1 allow_null=0 actions_ref=Menu_actions actionvar=MenuAact
			#menu_gum header="$Header" options=COMPONENTS outvar=SELECTED_COMPONENTS multi=1
			#menu_fzf header="$Header" options=COMPONENTS outvar=SELECTED_COMPONENTS multi=1 cursor">"
			rc=$?
		
			if [[ -n "$MenuAact" ]]; then
				MenuAact=$(get_array_key "$MenuAact" Action_labels)
			fi
		
			if [[ $rc -gt 0 ]]; then
				[[ "$rc" == "${MENU_CHOOSE_EXIT_RC:-3}" ]] && exit 0
				[[ "$rc" == "${MENU_CHOOSE_ABORT_RC:-130}" ]] && exit 0
				return "$rc"
			else
				case "$MenuAact" in
					cancel) return "${MENU_CHOOSE_CANCEL_RC:-2}" ;;
					exit) exit 0 ;;
				esac
			fi
			
			component_action_menu || continue
			
			break
		done
		
	else
	
		if is_array_single COMPONENTS; then
			echo -e "${BLUE_BOLD}🟦  $(get_label available_component):${NC}\n"
		else
			echo -e "${BLUE_BOLD}🟦  $(get_label available_components):${NC}\n"
		fi
	
		components_list COMPONENTS || return 1
		component_choose_menu || return 1
		
		# Внутрішній цикл для роботи з обраними компонентами
		while true; do
			component_selected_list_menu || continue
			component_action_menu || continue
		
			if is_array_single SELECTED_COMPONENTS; then
				question="$(get_label q_continue_working_with_selected_component)"
			else
				question="$(get_label q_continue_working_with_selected_components)"
			fi
		
			echo
			read -rp "$question (y/n): " ans
			[[ "$ans" =~ ^[Yy]$ ]] || break
		done
	fi

}

function component_choose_menu() {

	local -A ALREADY_SELECTED

	menu_divider
	echo -e "☑️  Обрати"
    echo -e "${LIGHT_GRAY}Вибірково (наприклад: 1,3,5-7)${NC}"
    echo -e "${LIGHT_GRAY}Усі (натисніть Enter)${NC}"
	menu_nav
    
	while true; do
		
		echo
		read -rp "> " input
		
        case "$input" in
			"")  # Порожній ввід — вибрати всі
				SELECTED_COMPONENTS=("${COMPONENTS[@]}")
                return 0
                ;;
            c) return 1;;
            x) exit 0;;
            *)
				choose_items "$input" COMPONENTS SELECTED_COMPONENTS
				
				if ! is_array_empty SELECTED_COMPONENTS; then
                    return 0
                fi
				;;
        esac
    done
}

function component_selected_list_menu() {

	if is_array_empty SELECTED_COMPONENTS; then
		log_warn "$(get_label no_components_selected)"
		return 1
	fi
	
	if is_array_single SELECTED_COMPONENTS; then
	  echo -e "\n${CYAN_BOLD}☑️  $(get_label selected_component):${NC}\n"
	else
	  echo -e "\n${CYAN_BOLD}☑️  $(get_label selected_components):${NC}\n"
	fi

	components_list SELECTED_COMPONENTS || return 1
}

function component_action() {

	if is_array_empty SELECT; then
		log_error "Нічого не вибрано"
		return 1
	fi
		
	# Дії
	if ! function_isset "${TYPE}_component_action"; then
		log_error "Функції ${TYPE}_component_action не знайдено"
		return 1
	fi
	
	"${TYPE}_component_action" SELECT
}

function component_action_menu() {
	
	if is_array_empty SELECTED_COMPONENTS; then
		log_warn "$(get_label no_components_selected)"
		return 1
	fi
	
	local -A action_menu_labels=()
	local action_menu_items=()
	
	if function_isset "${TYPE}_action_menu_items"; then
	
		"${TYPE}_action_menu_items" action_menu_items action_menu_labels
	fi
	
	local Header
	if array_key_has_value "${TYPE}_menu_header" action_menu_labels; then
		Header="${action_menu_labels[${TYPE}_menu_header]}"
	elif array_key_has_value "$TYPE" HEADER_LABELS; then
		Header="${HEADER_LABELS[$TYPE]}"
	else
		Header="$TYPE"
	fi
	
	if [[ "$MENU_CHOOSE_TYPE" == "menu_choose" ]] && ! is_array_empty "action_menu_items" && ! is_array_empty "action_menu_labels"; then
		
		ACTION=()

		component_menu_choose items=action_menu_items labels=action_menu_labels outvar=ACTION multi=1 allow_null=0 header="$Header"
		rc=$?
		
		if [[ $rc -gt 0 ]]; then
			return "$rc"
		fi
	
	else

	  # Виклик відображення меню з відповідного модуля
	  "show_${TYPE}_action_menu"
	
	  local prev_input=""
      while true; do
		
		echo
		# показуємо попереднє введення, якщо є
		read -re -i "$prev_input" -p "> " input
		
		# Розділяємо введене значення по комах або пробілах
		IFS=', ' read -ra choices <<< "$input"
		# прибирає пусті
		filtered_choices=()
		for c in "${choices[@]}"; do
			[[ -n "$c" ]] && filtered_choices+=("$c")
		done
		choices=("${filtered_choices[@]}")
		
		ACTION=()
		
		# Парсинг вибору з відповідного модуля
        "parse_${TYPE}_action_choices"
		rc=$?
		
		if [[ $rc -eq 2 ]]; then
            prev_input="$input"
            continue # invalid
        elif [[ $rc -eq 1 ]]; then
            return 1
        fi

		# Якщо ACTION непорожній
		if ! is_array_empty ACTION; then
            break
        fi
      
	  done
	fi
	
	# Виконуємо дії
	if is_array_single SELECTED_COMPONENTS; then
		echo -e "\n⏳  $(get_label component_processing)...\n"
	else
		echo -e "\n⏳  $(get_label components_processing)...\n"
	fi
	
	"action_${TYPE}_components" ACTION SELECTED_COMPONENTS
}

function pause() {
    echo
	read -rp "Натисніть Enter, щоб продовжити..." _
}

function component_menu(){
  
	if ! declare -p TYPE &>/dev/null; then
		log_error "Не вдалося визначити тип компонента"
		return 1
	else
		if ! declare -p "${TYPE}_labels" &>/dev/null; then
			log_warn "Заголовків '${TYPE}_labels' для '${HEADER_LABELS[$TYPE]:-$TYPE}' не знайдено"
		fi
	fi
  
	while true; do

		component_filter_menu || {
			rc=$?
			return "$rc"
		}
		search_components || continue
		component_list_menu || continue
	
		break
	done
}

function component_type_menu(){
  
	if ! declare -p TYPE &>/dev/null; then
		log_error "Не вдалося визначити тип компонента"
		return 1
	else
		if ! declare -p "${TYPE}_labels" &>/dev/null; then
			log_warn "Заголовків '${TYPE}_labels' для '${HEADER_LABELS[$TYPE]:-$TYPE}' не знайдено"
		fi
	fi
  
	while true; do

		component_select_menu || {
			rc=$?
			return "$rc"
		}
	
		break
	done
}

function get_component_file() {
    local type_ref="$1"      # може бути значення або ім'я змінної
    local -n file_ref="$2"   # змінна, куди записуємо результат

    # Якщо type_ref — ім'я існуючої змінної, використовуємо її значення
    if [[ ${!type_ref+x} ]]; then
        type_ref="${!type_ref}"
    fi

    # Формуємо шлях
    file_ref="$SCRIPT_DIR/component-$type_ref"
}

function source_component_file(){
	local comp_file
	get_component_file TYPE comp_file
	
	# Перевіряємо чи існує файл перед source
	if [[ -f $comp_file ]]; then
		source "$comp_file"
	else
		log_error "Модуль $comp_file для '${HEADER_LABELS[$TYPE]:-$TYPE}' не знайдено"
		return 1
	fi
}

# ===================== MAIN MENU =====================
while true; do
    choose_type_menu || continue

    get_component_file TYPE comp_file
	# Перевіряємо чи існує файл перед source
	if [[ -f $comp_file ]]; then
		source "$comp_file"
	else
		log_error "Модуль $comp_file для '${HEADER_LABELS[$TYPE]:-$TYPE}' не знайдено"
		continue
	fi

	if function_isset "${TYPE}_component_menu"; then
		"${TYPE}_component_menu" || continue
	else
		component_menu || continue
	fi
	
done
