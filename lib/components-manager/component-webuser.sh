declare -gA webuser_labels=(
  [get_components]='Отримуємо веб-користувачі'
  [no_components_found]='Не знайдено жодного веб-користувача'
  [no_components_found_with_filter]='Не знайдено жодного веб-користувача з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступний веб-користувач'
  [available_components]='Доступні веб-користувачі'
  [no_components_selected]='Веб-користувачі не вибрані'
  [selected_component]='Обраний веб-користувач'
  [selected_components]='Обрані веб-користувачі'
  [component_processing]='Обробка веб-користувача'
  [components_processing]='Обробка веб-користувачів'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраним веб-користувачем?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними веб-користувачами?'
)

# Перевірка існування веб-користувача
function is_webuser() {
    local user="$1"
	
	if ! id "$user" &>/dev/null; then
        return 1
    fi
    
    # Перевірка наявності групи webusers у користувача
    if id -nG "$user" | grep -qw "webusers"; then
        return 0
    fi
	
	return 1
}

function webuser_isset() {
	local user="$1"

	is_webuser "$user"
}

function show_webuser_filter_menu(){
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}:"
    echo "Усі"
	echo "1) Із SSH-доступом"
	echo "2) Без SSH-доступу"
	echo "3) Заблоковані"
	echo "s) Шукати за назвою"
	menu_nav
}

function parse_webuser_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
			1) FILTER+=("shell") ;;
			2) FILTER+=("no_shell") ;;
			3) FILTER+=("locked") ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function get_webuser_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local ITEMS=()
  local _Filters=()
  
  _Filters=("webuser")
  
  readarray -t ITEMS < <(get_users Filters "$SEARCH" _Filters)
  
  _out=("${ITEMS[@]}")
}

function show_webuser_action_menu() {
	menu_header "🛠️  Керування веб-користувачами:"
    echo "1) Додати нового веб-користувача"
    echo "2) Заблокувати"
    echo "3) Заблокувати пароль"
    echo "4) Заблокувати Shell-доступ"
    echo "5) Розблокувати"
	echo "6) Розблокувати пароль"
	echo "7) Розблокувати Shell-доступ"
    echo "8) Видалити"
	echo "9) Змінити домашню директорію"
	echo "10) Змінити Shell-доступ"
	echo "11) Змінити пароль"
	echo "12) Додати до групи"
    echo "13) Видалити з групи"
	menu_header "📊  Інформація та діагностика:"
	echo "21) Показати дані веб-користувачів"
    echo "22) Показати інформацію про веб-користувача"
	echo "23) Перевірити домашню директорію"
    echo "24) Перевірити Shell-доступ"
	echo "25) Перевірити ID"
	echo "26) Перевірити групи"
	echo "27) Перевірити FTP-користувачів"
	menu_nav
}

function parse_webuser_action_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Нічого не вибрано"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) ACTION+=("add") ;;
			2) ACTION+=("lock") ;;
			3) ACTION+=("lock_passwd") ;;
			4) ACTION+=("lock_shell") ;;
			5) ACTION+=("unlock") ;;
			6) ACTION+=("unlock_passwd") ;;
			7) ACTION+=("unlock_shell") ;;
			8) ACTION+=("delete") ;;
			9) ACTION+=("change_home") ;;
			10) ACTION+=("change_shell") ;;
			11) ACTION+=("passwd") ;;
			12) ACTION+=("add_to_group") ;;
            13) ACTION+=("delete_from_group") ;;
			21) ACTION+=("data") ;;
			22) ACTION+=("info") ;;
			23) ACTION+=("home") ;;
			24) ACTION+=("shell") ;;
			25) ACTION+=("id") ;;
			26) ACTION+=("groups") ;;
			27) ACTION+=("ftpusers") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function action_webuser_components() {
  local -n actions="$1"
  local -n users="$2"
  local label user value
  
  local -A action_names=(
    [add]="Створення веб-користувача"
	[data]="Дані веб-користувачів"
	[data_single]="Дані веб-користувача {user}"
	[info]="Інформація про веб-користувача"
	[info_single]="Інформація про веб-користувача {user}"
	[home]="Домашня директорія веб-користувачів"
	[home_single]="Домашня директорія веб-користувача {user}"
	[shell]="Shell-доступ веб-користувачів"
	[shell_single]="Shell-доступ веб-користувача {user}"
	[id]="UID і GID веб-користувачів"
	[id_single]="UID і GID веб-користувача {user}"
	[passwd]="Зміна паролю веб-користувачів"
	[passwd_single]="Зміна паролю веб-користувача {user}"
	[change_shell]="Зміна Shell-доступ веб-користувачів"
	[change_shell_single]="Зміна Shell-доступ веб-користувача {user}"
	[change_home]="Зміна домашньої директорії веб-користувачів"
	[change_home_single]="Зміна домашньої директорії веб-користувача {user}"
	[groups]="Групи веб-користувачів"
	[groups_single]="Групи веб-користувача {user}"
	[delete]="Видалення веб-користувачів"
	[delete_single]="Видалення веб-користувача {user}"
	[lock]="Блокування веб-користувачів"
	[lock_single]="Блокування веб-користувача {user}"
	[unlock]="Розблокування веб-користувачів"
	[unlock_single]="Розблокування веб-користувача {user}"
	[add_to_group]="Додавання веб-користувачів до групи"
	[add_to_group_single]="Додавання веб-користувача {user} до групи"
	[delete_from_group]="Видалення веб-користувачів з групи"
	[delete_from_group_single]="Видалення веб-користувача {user} з групи"
	[ftpusers]="FTP-користувчі веб-користувачів"
	[ftpusers_single]="FTP-користувчі веб-користувача {user}"
  )
  
  action_webuser_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    # заміна {user} на значення змінної $user
	text="${text//\{user\}/${user:-}}"
    echo "$text"
  }
  
  is_array_empty users && log_warn "Веб-користувачі не вказані" && return
  is_array_empty actions && log_warn "Дії не вказані" && return
  
  for action in "${actions[@]}"; do
	
	user="${users[0]:-}"
	if is_array_single users && array_key_has_value "${action}_single" action_names; then
		label=$(action_webuser_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_webuser_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
	  add) add-webuser ;;
	  info) users_info users ;;
	  data) users_table users ;;
	  passwd) change_users_passwd users ;;
	  home) users_table users "idx name home" ;;
	  change_home) change_users_dirs users ;;
	  id) users_table users "idx name uid gid groups_ids" ;;
	  lock) lock_users users ;;
	  lock_passwd) lock_users_passwd users ;;
	  lock_shell) lock_users_shells users ;;
	  unlock) unlock_users users ;;
	  unlock_passwd) unlock_users_passwd users ;;
	  unlock_shell) unlock_users_shells users ;;
	  delete) delete_users users ;;
	  shell) users_table users "idx name shell" ;;
	  change_shell) change_users_shells users  ;;
	  groups) users_table users "idx name groups" ;;
	  add_to_group) add_users_to_roup users ;;
	  delete_from_group) delete_users_from_roup users ;;
	  ftpusers)
		
		local TYPE="ftpuser"
		get_component_file TYPE comp_file
		if [[ -f $comp_file ]]; then
			source "$comp_file"
		else
			log_error "Модуль для $TYPE не знайдено: $comp_file"
			return 2
		fi
		
		local user_str=$(IFS=','; echo "${users[*]}")
		local ftpusers=()
  
		readarray -t ftpusers < <(get-ftpuser user="$user_str" 2>/dev/null | awk '{print $1}' | paste -sd, -)
		
		ftpusers_table ftpusers "idx name uid gid home shell active user"
		;;
      *) log_error "Невідома дія: $action" ;;
	esac
  
  done
}

function webuser_filter_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[all]="Усі"
		[admin]="Адміністратори"
		[service]="Сервісні"
		[root]="Root"
		[required]="Обов'язкові"
		[shell]="Із SSH-доступом"
		[no_shell]="Без SSH-доступу"
		[no_passwd]="Без паролю"
		[locked]="Заблоковані"
		[search]="Шукати за назвою"
	)

	Items=(
		all
		active
		required
		optional
		extra
		search
	)
}

function webuser_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[add]="Додати нового веб-користувача"
		[lock]="Заблокувати"
		[lock_passwd]="Заблокувати пароль"
		[lock_shell]="Заблокувати Shell-доступ"
		[unlock]="Розблокувати"
		[unlock_passwd]="Розблокувати пароль"
		[unlock_shell]="Розблокувати Shell-доступ"
		[delete]="Видалити"
		[change_home]="Змінити домашню директорію"
		[change_shell]="Змінити Shell-доступ"
		[passwd]="Змінити пароль"
		[add_to_group]="Додати до групи"
		[delete_from_group]="Видалити з групи"
		[data]="Показати дані веб-користувачів"
		[info]="Показати інформацію про веб-користувача"
		[home]="Перевірити домашню директорію"
		[shell]="Перевірити Shell-доступ"
		[id]="Перевірити ID"
		[groups]="Перевірити групи"
		[ftpusers]="Перевірити FTP-користувачів"
	)
	
	Items=(
        add
		lock
		lock_passwd
		lock_shell
		unlock
		unlock_passwd
		unlock_shell
		delete
		change_home
		change_shell
		passwd
		add_to_group
		delete_from_group
		data
		info
		home
		shell
		id
		groups
		ftpusers
	)
}
