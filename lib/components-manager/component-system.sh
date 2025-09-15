declare -gA system_labels=()

function show_system_menu_select() {
	menu_header "⚙️  Налаштування:"
    echo "1) OS Login"
	echo "2) Доступні Shells для входу"
	echo "3) Встановити Веб-панель"
	menu_nav
}

function parse_system_menu_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Порожнє значення"
		return 2
	fi

    for choice in "${choices[@]}"; do
        case "$choice" in
            1) SELECT+=("os_login") ;;
			2) SELECT+=("shells") ;;
			3) SELECT+=("init_webpanel") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function system_component_action() {
  local -n actions="$1"
  local label

  is_array_empty actions && log_warn "Нічого не вибрано" && return 2
  
  local -A action_names=(
	[os_login]="Перевірка OS Login"
	[shells]="Доступні Shells для входу"
  )
  
  system_component_action__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    echo "$text"
  }
  
  for action in "${actions[@]}"; do
	
	if array_key_has_value "$action" action_names; then
        label=$(system_component_action__get_label "$action")
		echo -e "\n${YELLOW_BOLD}$label${NC}"
    fi
	
	echo
	case "$action" in
		os_login) check-oslogin ;;
		shells) available_shells_list ;;
		init_webpanel) init-webpanel ;;
	esac
  
  done
}

function system_component_menu() {
	component_type_menu
}

function system_select_menu_items(){

	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[os_login]="OS Login"
		[shells]="Доступні Shells для входу"
		[init_webpanel]="Встановити Веб-панель"
	)
	
	Items=(
        os_login
		shells
		init_webpanel
	)	
}
