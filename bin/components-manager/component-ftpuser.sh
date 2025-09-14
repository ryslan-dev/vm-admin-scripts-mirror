declare -gA ftpuser_labels=(
  [get_components]='Отримуємо FTP-користувачі'
  [no_components_found]='Не знайдено жодного FTP-користувача'
  [no_components_found_with_filter]='Не знайдено жодного FTP-користувача з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступний FTP-користувач'
  [available_components]='Доступні FTP-користувачі'
  [no_components_selected]='FTP-користувачі не вибрані'
  [selected_component]='Обраний FTP-користувач'
  [selected_components]='Обрані FTP-користувачі'
  [component_processing]='Обробка FTP-користувача'
  [components_processing]='Обробка FTP-користувачів'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраним FTP-користувачем?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними FTP-користувачами?'
)

# Перевірка існування ftp-користувача
function ftpuser_isset() {
	get-ftpuser "$1" &>/dev/null
}

function get_ftpusers() {
    local -n filters="$1"
    local search="${2:-}"
	local user="${3:-}"
	
	local shell active
	
	# Shell
	if in_array "shell" filters && ! in_array "no_shell" filters; then
		shell="/bin/bash"
	elif ! in_array "shell" filters && in_array "no_shell" filters; then
		shell="/bin/false"
	else
		shell=""
	fi
	
	# Active
	if in_array "active" filters && ! in_array "inactive" filters; then
		active=1
	elif ! in_array "active" filters && in_array "inactive" filters; then
		active=0
	else
		active=""
	fi

	get-ftpuser user="$user" shell="$shell" active="$active" s="$search" 2>/dev/null | awk '{print $1}'
}

function ftpusers_table() {
	local -n Users="$1"
    shift
	
    local -a Items=()

    # --- Default Items ---
    if (( $# == 0 )); then
        Items=(idx name uid gid home shell active user)
    else
        local raw="$*"
        raw="${raw//,/ }"
        raw="${raw//+([[:space:]])/ }"
        raw="${raw## }"
        raw="${raw%% }"
        IFS=' ' read -r -a Items <<< "$raw"
    fi

    # --- Labels ---
    local -A labels=(
        [idx]="#"
        [name]="Name"
        [uid]="UID"
        [gid]="GID"
        [home]="Home DIR"
        [shell]="Shell"
        [active]="Active"
		[user]="Local User"
    )
	
	# --- Формуємо рядок шапки у правильному порядку ---
    local labels_str=""
    for key in "${Items[@]}"; do
        labels_str+="${labels[$key]:-$key}|"
    done
    labels_str=${labels_str%|}

    # --- Отримуємо дані для всіх користувачів ---
    local data=""
    if (( ${#Users[@]} > 0 )); then
        # Об'єднуємо в одне ім'я через кому
        local names=$(IFS=','; echo "${Users[*]}")
        data=$(get-ftpuser "$names" 2>/dev/null || true)
    fi
	
    if [[ -z "$data" ]]; then
        return 1
    fi
	
    # --- Будуємо мапу UID -> username ---
    local uid_map=""
	if in_array "user" Items; then
		while IFS=: read -r uname _ uid _; do
			uid_map+="$uid:$uname|"
		done < <(getent passwd)
		uid_map=${uid_map%|}
	fi

    # Читаємо дані з stdin
    awk -v items="${Items[*]}" \
        -v gray="$GRAY" \
        -v nc="$NC" \
        -v labels_str="$labels_str" \
        -v uid_map="$uid_map" \
	'
    BEGIN {
        split(items, item_arr)
        split(labels_str, label_arr, "|")
        for(i=1;i<=length(item_arr);i++) {
			key = item_arr[i]
			val = label_arr[i]
			label[key] = val
			if(length(val) > max_w[key]) max_w[key] = length(val)
		}
        
        # Мапа UID -> username
        split(uid_map, pairs, "|")
        for(i in pairs) {
            split(pairs[i], kv, ":")
            uid2user[kv[1]] = kv[2]
        }
		
		idx = 1
    }
    {
        name=$1; uid=$2; gid=$3; home=$4; shell=$5; active=$6
		
		# --- Зберігаємо дані ---
        for(i=1;i<=length(item_arr);i++) {
            key = item_arr[i]
            if(key=="idx") val=idx
            else if(key=="name") val=name
            else if(key=="uid") val=uid
            else if(key=="gid") val=gid
            else if(key=="home") val=home
            else if(key=="shell") val=shell
            else if(key=="active") val=(active==1?"так":"ні")
            else if(key=="user") val=(uid in uid2user ? uid2user[uid] : "-")
            else val=""
            data[idx,key] = val
            if(length(val) > max_w[key]) max_w[key] = length(val)
        }
        idx++

    }
    END {
        nrows = idx - 1

       # --- Шапка ---
        line = ""
        for(i=1;i<=length(item_arr);i++) {
            key = item_arr[i]
            if(i>1) line = line " " gray "|" nc " "
            fmt = "%-" max_w[key] "s"
            line = line sprintf(fmt, label[key])
        }
        printf "%s\n", line

        # --- Роздільник ---
        sep_len = 0
        for(i=1;i<=length(item_arr);i++) sep_len += max_w[item_arr[i]]
        sep_len += 3*(length(item_arr)-1)
        sep_line = ""
        for(i=1;i<=sep_len;i++) sep_line = sep_line "—"
        printf "%s%s%s\n", gray, sep_line, nc

        # --- Дані ---
        for(r=1;r<=nrows;r++) {
            line = ""
            for(i=1;i<=length(item_arr);i++) {
                key = item_arr[i]
                if(i>1) line = line " " gray "|" nc " "
                fmt = "%-" max_w[key] "s"
                line = line sprintf(fmt, data[r,key])
            }
            printf "%s\n", line
        }
    }' <<< "$data"
}

function ftpuser_info() {
    local ftpuser="$1"

    # ANSI-кольори
    local RED='\033[0;31m'
    local YELLOW='\033[1;33m'
    local GREEN='\033[0;32m'
    local CYAN='\033[0;36m'
    local NC='\033[0m'

    # Перевірка існування FTP-користувача
    if [[ -z "$ftpuser" ]]; then
        log_error "Не вказано FTP-Користувача"
        return 1
    fi
	
    # --- Отримуємо дані FTP-користувача ---
    local data
    data=$(get-ftpuser "$ftpuser" 2>/dev/null)
    if [[ -z "$data" ]]; then
        log_error "FTP-користувача $ftpuser не знайдено"
        return 1
    fi
	
	# --- Розбираємо рядок FTP-користувача ---
    local name uid gid homedir shell active
    read -r name uid gid homedir shell active <<< "$data"
	
	local_user=$(getent passwd "$user" | cut -d: -f1)

	# --- Основне ---
    echo "Ім’я: $name"
	echo "Локальний користувач: $local_user"
    echo "UID: $uid"
    echo "GID: $gid"
    echo "Домашня директорія: $homedir"
    echo "Shell-доступ: $shell"
    echo "Активний: $([[ $active -eq 1 ]] && echo так || echo ні)"

}

function ftpusers_info(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if ! is_array_single Users; then
	    echo -e "\n${CYAN_BOLD}$index FTP-користувач $user:${NC}\n"
	  fi
	  ftpuser_info "$user"
	  echo
	  ((index++))
	done
}

function change_ftpusers_passwd(){
	local -n Users="$1"
	
	local index=1
    for user in "${users[@]}"; do
	  if ftpuser_isset "$user"; then
		
		local newpasswd
		read -p "Новий пароль FTP-користувача $user: " newpasswd
		
		if [[ -n "$newpasswd" ]]; then
		  if update-ftpuser "$user" passwd="$newpasswd"; then
			log_success "Пароль FTP-користувача $user змінено"
		  else
			log_error "Не вдалося змінити пароль FTP-користувача $user"
		  fi
		else
		  echo "Зміну паролю FTP-користувача $user скасовано"
		fi
	    
	  else
		log_error "FTP-користувача $user не знайдено"
	  fi
	  ((index++))
	done
}

function change_ftpusers_home(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if ! is_array_single Users; then
	    echo -e "\n${CYAN_BOLD}$index FTP-користувач $user:${NC}\n"
	  fi
	  
	  local homedir=$(get-ftpuser "$user" 2>/dev/null | awk '{print $4}')
	  local newdir
	  
	  echo "Поточна домашня директорія: $homedir"
	  read -p "Назва нової директорії: " newdir
	  
	  if [[ -n "$newdir" ]]; then
		if update-ftpuser "$user" home="$newdir" &>/dev/null; then
			log_success "Домашню директорію FTP-користувача $user оновлено"
		else
			log_error "Не вдалося оновити домашню директорію FTP-користувача $user"
		fi
	  else
		  echo "Зміну домашньої директорії FTP-користувача $user скасовано"
	  fi
	  
	  echo
	  ((index++))
	done
}

function enable_ftpusers_shell(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if ! is_array_single Users; then
	    echo -e "\n${CYAN_BOLD}$index FTP-користувач $user:${NC}\n"
	  fi
	  
	  local shell=$(get-ftpuser "$user" 2>/dev/null | awk '{print $5}')
	  local newshell
	  
	  echo "Поточний Shell-доступ: $shell"
	  newshell="/bin/bash"
	  
	  if [[ -n "$newshell" ]]; then
		if update-ftpuser "$user" shell="$newshell" &>/dev/null; then
			log_success "Shell-доступ FTP-користувача $user увімкнено ($newshell)"
		else
			log_error "Не вдалося оновити Shell-доступ FTP-користувача $user"
		fi
	  else
		  echo "Зміну Shell-доступу FTP-користувача $user скасовано"
	  fi
	  
	  echo
	  ((index++))
	done
}

function disable_ftpusers_shell(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if ! is_array_single Users; then
	    echo -e "\n${CYAN_BOLD}$index FTP-користувач $user:${NC}\n"
	  fi
	  
	  local shell=$(get-ftpuser "$user" 2>/dev/null | awk '{print $5}')
	  local newshell
	  
	  echo "Поточний Shell-доступ: $shell"
	  newshell="/bin/false"
	  
	  if [[ -n "$newshell" ]]; then
		if update-ftpuser "$user" shell="$newshell" &>/dev/null; then
			log_success "Shell-доступ FTP-користувача $user вимкнено ($newshell)"
		else
			log_error "Не вдалося оновити Shell-доступ FTP-користувача $user"
		fi
	  fi
	  
	  echo
	  ((index++))
	done
}

function activate_ftpusers_shell(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if ! is_array_single Users; then
	    echo -e "\n${CYAN_BOLD}$index FTP-користувач $user:${NC}\n"
	  fi
	  
	  local active=$(get-ftpuser "$user" 2>/dev/null | awk '{print $6}')
	  
	  if (( ! active )); then
		if update-ftpuser "$user" active=1 &>/dev/null; then
			log_success "FTP-користувача $user активовано"
		else
			log_error "Не вдалося активувати FTP-користувача $user"
		fi
	  else
		log_warn "FTP-користувач $user уже активовано;"
	  fi
	  
	  echo
	  ((index++))
	done
}

function deactivate_ftpusers_shell(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if ! is_array_single Users; then
	    echo -e "\n${CYAN_BOLD}$index FTP-користувач $user:${NC}\n"
	  fi
	  
	  local active=$(get-ftpuser "$user" 2>/dev/null | awk '{print $6}')
	  
	  if (( active )); then
		if update-ftpuser "$user" active=1 &>/dev/null; then
			log_success "FTP-користувача $user деактивовано"
		else
			log_error "Не вдалося деактивувати FTP-користувача $user"
		fi
	  else
		log_warn "FTP-користувач $user уже деактивовано;"
	  fi
	  
	  echo
	  ((index++))
	done
}

function delete_ftpusers(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  delete-ftpuser "$user"
	  echo
	  ((index++))
	done
}

function show_ftpuser_filter_menu(){
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}:"
    echo "Усі"
	echo "1) Активні"
	echo "2) Неактивні"
	echo "3) Із SSH-доступом"
	echo "4) Без SSH-доступу"
	echo "5) Локального користувача"
	echo "s) Шукати за назвою"
	menu_nav
}

function parse_ftpuser_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
			1) FILTER+=("active") ;;
			2) FILTER+=("inactive") ;;
			3) FILTER+=("shell") ;;
			4) FILTER+=("no_shell") ;;
			5) FILTER+=("user") 
			  # Select users
			  
			  local users_filter=()
			  local COMPONENTS=()
			  get_user_components users_filter COMPONENTS
			  
			  [[ -z "$COMPONENTS" ]] && {
				log_error "Користувачів не знайдено"
				return 2
			  }
			  
			  echo -e "\n${BOLD}Виберіть користувача:${NC}\n"
			  
			  components_list COMPONENTS
			  component_choose_menu
			  
			  [[ -n "${SELECTED_COMPONENTS:-}" ]] && {
				declare -ga SELECTED_LOCAL_USERS
				SELECTED_LOCAL_USERS=("${SELECTED_COMPONENTS[@]}")
				SELECTED_COMPONENTS=()
				#log_success "Користувачі вибрані: $(IFS=, ; echo "${SELECTED_COMPONENTS[*]}")"
				continue
			  } || {
				log_error "Користувачів не вибрано"
				return 2
			  }

			  ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function get_ftpuser_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local ITEMS=()
  
  local user="$(IFS=, ; echo "${SELECTED_LOCAL_USERS[*]}")"
  
  readarray -t ITEMS < <(get_ftpusers Filters "${SEARCH:-}" "${user:-}")
  
  _out=("${ITEMS[@]}")
}

function show_ftpuser_action_menu() {
	menu_header "🛠️  Керування FTP-користувачами:"
    echo "1) Додати нового FTP-користувача"
    echo "2) Активувати"
	echo "3) Деактивувати"
    echo "4) Змінити домашню директорію"
	echo "5) Змінити пароль"
	echo "6) Увімкнути Shell-доступ"
	echo "7) Вимкнути Shell-доступ"
	echo "8) Видалити"
	menu_header "📊  Інформація та діагностика:"
	echo "21) Показати дані FTP-користувачів"
    echo "22) Показати інформацію про FTP-користувача"
	echo "23) Перевірити домашню директорію"
    echo "24) Перевірити Shell-доступ"
	echo "25) Перевірити ID"
	menu_nav
}

function parse_ftpuser_action_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Порожнє значення"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) ACTION+=("add") ;;
			2) ACTION+=("activate") ;;
			3) ACTION+=("deactivate") ;;
			4) ACTION+=("change_home") ;;
			5) ACTION+=("passwd") ;;
			6) ACTION+=("enable_shell") ;;
			7) ACTION+=("disable_shell") ;;
			8) ACTION+=("delete") ;;
			21) ACTION+=("data") ;;
			22) ACTION+=("info") ;;
			23) ACTION+=("home") ;;
			24) ACTION+=("shell") ;;
			25) ACTION+=("id") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function action_ftpuser_components() {
  local -n actions="$1"
  local -n users="$2"
  local label user value
  
  local -A action_names=(
    [add]="Створення FTP-користувача"
	[data]="Дані FTP-користувачів"
	[data_single]="Дані FTP-користувача {user}"
	[info]="Інформація про FTP-користувача"
	[info_single]="Інформація про FTP-користувача {user}"
	[home]="Домашня директорія FTP-користувачів"
	[home_single]="Домашня директорія FTP-користувача {user}"
	[shell]="Shell-доступ FTP-користувачів"
	[shell_single]="Shell-доступ FTP-користувача {user}"
	[id]="UID і GID FTP-користувачів"
	[id_single]="UID і GID FTP-користувача {user}"
	[passwd]="Зміна паролю FTP-користувачів"
	[passwd_single]="Зміна паролю FTP-користувача {user}"
	[activate]="Активувація FTP-користувачів"
	[activate_single]="Активувація FTP-користувача {user}"
	[deactivate]="Деактивувація FTP-користувачів"
	[deactivate_single]="Деактивувація FTP-користувача {user}"
	[enable_shell]="Увімкнення Shell-доступ користувачів"
	[enable_shell_single]="Увімкнення Shell-доступ користувача {user}"
	[disable_shell]="Вимкнення Shell-доступ користувачів"
	[disable_shell_single]="Вимкнення Shell-доступ користувача {user}"
	[change_home]="Зміна домашньої директорії FTP-користувачів"
	[change_home_single]="Зміна домашньої директорії FTP-користувача {user}"
	[delete]="Видалення FTP-користувачів"
	[delete_single]="Видалення FTP-користувача {user}"
  )
  
  action_ftpuser_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    # заміна {user} на значення змінної $user
	text="${text//\{user\}/${user:-}}"
    echo "$text"
  }
  
  is_array_empty users && log_warn "FTP-користувачі не вказані" && return
  is_array_empty actions && log_warn "Дії не вказані" && return
  
  for action in "${actions[@]}"; do
	
	user="${users[0]:-}"
	if is_array_single users && array_key_has_value "${action}_single" action_names; then
		label=$(action_ftpuser_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_ftpuser_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
	  add) add-ftpuser ;;
	  data) ftpusers_table users ;;
	  info) ftpusers_info users ;;
	  id) ftpusers_table users "idx name uid gid" ;;
	  home) ftpusers_table users "idx name home" ;;
	  shell) ftpusers_table users "idx name shell" ;;
	  passwd) change_ftpusers_passwd users;;
	  change_home) change_ftpusers_home users ;;
	  enable_shell) enable_ftpusers_shell users ;;
	  disable_shell) disable_ftpusers_shell users ;;
	  activate) activate_ftpusers_shell users ;;
	  deactivate) deactivate_ftpusers_shell users ;;
	  delete) delete_ftpusers users ;;
      *) log_error "Невідома дія: $action" ;;
	esac
  
  done
}

function ftpuser_filter_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[all]="Усі"
		[active]="Активні"
		[inactive]="Неактивні"
		[shell]="Із SSH-доступом"
		[no_shell]="Без SSH-доступу"
		[user]="Локального користувача"
		[search]="Шукати за назвою"
	)

	Items=(
		all
		active
		inactive
		shell
		no_shell
		user
		search
	)
}

function ftpuser_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[add]="Додати нового FTP-користувача"
		[activate]="Активувати"
		[deactivate]="Деактивувати"
		[change_home]="Змінити домашню директорію"
		[passwd]="Змінити пароль"
		[enable_shell]="Увімкнути Shell-доступ"
		[disable_shell]="Вимкнути Shell-доступ"
		[delete]="Видалити"
		[data]="Показати дані FTP-користувачів"
		[info]="Показати інформацію про FTP-користувача"
		[home]="Перевірити домашню директорію"
		[shell]="Перевірити Shell-доступ"
		[id]="Перевірити ID"
	)
	
	Items=(
		add
		activate
		deactivate
		change_home
		passwd
		enable_shell
		disable_shell
		delete
		data
		info
		home
		shell
		id
	)
}
