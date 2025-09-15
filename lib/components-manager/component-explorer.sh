declare -gA explorer_labels=()

function show_explorer_menu_select() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}:"
    echo "1) Shell Explorer"
	echo "2) Shell Explorer (двопанельний)"
	echo "3) Midnight Commander (mc)"
	menu_nav
}

function parse_explorer_menu_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Порожнє значення"
		return 2
	fi

    for choice in "${choices[@]}"; do
        case "$choice" in
            1) SELECT+=("run_shell_explorer") ;;
			2) SELECT+=("run_shell_explorers") ;;
			3) SELECT+=("run_mc") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function explorer_component_action() {
  local -n actions="$1"
  local label

  is_array_empty actions && log_warn "Нічого не вибрано" && return 2
  
  local -A action_names=()
  
  explorer_component_action__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    echo "$text"
  }
  
  for action in "${actions[@]}"; do
	
	if array_key_has_value "$action" action_names; then
        label=$(explorer_component_action__get_label "$action")
		echo -e "\n${YELLOW_BOLD}$label${NC}"
    fi
	
	echo
	case "$action" in
		run_shell_explorer) shell-explorer ;;
		run_shell_explorers) shell-explorers ;;
		run_mc) mc ;;
	esac
  
  done
}

function explorer_component_menu() {
	component_type_menu
}

function explorer_select_menu_items(){

	local -n Items="$1"
	local -n Labels="$2"

	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[run_shell_explorer]="Shell Explorer"
		[run_shell_explorers]="Shell Explorer (двопанельний)"
		[run_mc]="Midnight Commander (mc)"
	)
	
	Items=(
        run_shell_explorer
		run_shell_explorers
		run_mc
	)
}
