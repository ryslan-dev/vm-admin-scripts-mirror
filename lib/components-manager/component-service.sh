declare -gA service_labels=(
  [get_components]='Отримуємо сервіси'
  [no_components_found]='Не знайдено сервіси'
  [no_components_found_with_filter]='Не знайдено сервіси з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступний сервіс'
  [available_components]='Доступні сервіси'
  [no_components_selected]='Сервіси не вибрані'
  [selected_component]='Обраний сервіс'
  [selected_components]='Обрані сервіси'
  [component_processing]='Обробка сервісу'
  [components_processing]='Обробка сервісів'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраним сервісом?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними сервісами?'
)

# ===================== FUNCTIONS =====================

# 🔍 Отримати пріоритет сервісу
function get_service_priority() {
  local service="$1"
  local priority
  
  priority="${SERVICE_PRIORITY[$service]:-unknown}"

  echo "$priority"
}

function get_service_description() {
  local service="$1"
  local description
  
  description="${SERVICE_DESCRIPTIONS[$service]:-}"
  
  echo "$description"
}

function print_services() {
  local -n arr=$1
  
  local basename priority description
  
  local index=1
  for service in "${arr[@]}"; do
    
	basename="${service%.service}"
	priority="$(get_service_priority "$service")"
	description="$(get_service_description "$service")"
    
	printf "%-4s %-40s | %-9s | %s\n" "$index" "$basename" "$priority" "$description"
	((index++))
  done
}

function get_service_components() {
  local -n filters="$1"
  local -n _out=$2
  _out=()
  
  local SERVICES=()
  local priority
  local priorities=()
  
  for f in "${filters[@]}"; do
    if in_array "$f" COMPONENT_PRIORITIES; then
		priorities+=("$f")
	fi
  done
  
  # 🔎 Отримуємо список сервісів
  if in_array "active" filters; then
    if [[ -z "$SEARCH" ]]; then
	  readarray -t SERVICES < <(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}')
	else
      readarray -t SERVICES < <(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}' | grep -i -- "$SEARCH")
	fi
  else
    if [[ -z "$SEARCH" ]]; then
	  readarray -t SERVICES < <(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}')
	else
      readarray -t SERVICES < <(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}' | grep -i -- "$SEARCH")
	fi
  fi
  
  # Якщо немає фільтрів пріоритетів — просто віддаємо весь список без циклів
  if is_array_empty priorities; then
    _out=("${SERVICES[@]}")
    return 0
  fi
  
  # Інакше — фільтруємо за пріоритетом
  for service in "${SERVICES[@]}"; do
    
	priority="$(get_service_priority "$service")"
    
    if in_array "$priority" priorities; then
        _out+=("$service")
    fi
  done
}

function action_service_components() {
  local -n actions="$1"
  local -n services="$2"
  local label service value
  
  local priority
  
  local -A action_names=(
    [status]="Вивід стану сервісів"
	[is_active]="Перевірка активності сервісів"
	[start]="Запуск сервісів"
	[stop]="Зупинка сервісів"
	[restart]="Перезапуск сервісів"
	[reload]="Перезавантаження сервісів"
	[is_enabled]="Перевірка увімкнення автозапуску сервісів"
	[enable]="Увімкнення автозапуску сервісів"
	[disable]="Вимкнення автозапуску сервісів"
	[mask]="Блокування сервісів"
	[unmask]="Розблокування сервісів"
	[edit]="Редагування юніт-файлу сервісів"
    [cat]="Вивід юніт-файлу сервісів"
	[show]="Вивід параметрів юніта сервісів"
	[list_dependencies]="Вивід залежностей сервісів"
	[list_unit_files]="Список юніт-файлів та їх стан"
	[help]="Довідка"
	[priority]="Перевірка пріоритету сервісів"
	[short_description]="Вивід коротких описів сервісів"
  )
  
  action_service_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    
	text="${text//\{service\}/${service:-}}"
    echo "$text"
  }
  
  is_array_empty services && log_warn "Сервіси не вказані" && return 2
  is_array_empty actions && log_warn "Дії не вказані" && return 2
  
  for action in "${actions[@]}"; do
	
	service="${services[0]:-}"
	if is_array_single services && array_key_has_value "${action}_single" action_names; then
		label=$(action_service_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_service_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
      status)
		local index=1
	    for service in "${services[@]}"; do
		  echo -e "${BOLD}$index Сервіс $service:${NC}"
		  systemctl status "$service" --no-pager || log_error "Не вдалося перевірити статус $service"
		  ((index++))
		done
        ;;
	  start)
        local index=1
	    for service in "${services[@]}"; do
		  systemctl start "$service" && status="$(get_log_success "$service запущено")" || status="$(get_log_error "Не вдалося запустити $service")"
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  ((index++))
		done
        ;;
      stop)
        local index=1
	    for service in "${services[@]}"; do
		  
		  priority="$(get_service_priority "$service")"
		  
		  if is_required "$service" "$priority"; then
			status="$(get_log_warn "$service не зупинено, бо є обов'язковим для роботи системи")"
		  else
		    systemctl stop "$service" && status="$(get_log_success "$service зупинено")" || status="$(get_log_error "Не вдалося зупинити $service")"
		  fi
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  
		  ((index++))
		done
        ;;
	  restart)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  systemctl restart "$service" && status="$(get_log_success "$service перезапущено")" || status="$(get_log_error "Не вдалося перезапустити $service")"
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  
		  ((index++))
		done
        ;;
	  reload)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  systemctl reload "$service" && status="$(get_log_success "$service перезавантажено")" || status="$(get_log_error "Не вдалося перезавантажити $service")"
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  
		  ((index++))
		done
        ;;
	  is_active)
		local index=1
	    for service in "${services[@]}"; do
		  status="$(systemctl is-active "$service" 2>/dev/null)" || status="$(get_log_error "Не вдалося перевірити активність $service")"
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  ((index++))
		done
        ;;
	  is_enabled)
		local index=1
	    for service in "${services[@]}"; do
		  status="$(systemctl is-enabled "$service" 2>/dev/null)" || status="$(get_log_error "Не вдалося перевірити увімкнення автозапуску $service")"
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  ((index++))
		done
        ;;
	  enable)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  systemctl enable "$service" && status="$(get_log_success "Автозапуск $service увімкнено")" || status="$(get_log_error "Не вдалося увімкнути автозапуск $service")"
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  
		  ((index++))
		done
	    ;;
      disable)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  priority="$(get_service_priority "$service")"
		  
		  if is_required "$service" "$priority"; then
			status="$(get_log_warn "Автозапуск $service не вимкнено, бо є обов'язковим для роботи системи")"
		  else
		    systemctl disable "$service" && status="$(get_log_success "Автозапуск $service вимкнено")" || status="$(get_log_error "Не вдалося вимкнути автозапуск $service")"
		  fi
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  
		  ((index++))
		done		
	    ;;
	  mask)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  priority="$(get_service_priority "$service")"
		  
		  if is_required "$service" "$priority"; then
			status="$(get_log_warn "Автозапуск $service не заблоковано, бо є обов'язковим для роботи системи")"
		  else
		    systemctl mask "$service" && status="$(get_log_success "$service заблоковано")" || status="$(get_log_error "Не вдалося заблокувати $service")"
		  fi
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  
		  ((index++))
		done
	    ;;
      unmask)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  systemctl unmask "$service" && status="$(get_log_success "$service розблоковано")" || status="$(get_log_error "Не вдалося розблокувати $service")"
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$status"
		  
		  ((index++))
		done
        ;;
	  edit)
	    local index=1
	    for service in "${services[@]}"; do
		  echo -e "${BOLD}$index Сервіс $service:${NC}"
		  systemctl edit "$service" || log_error "Не вдалося редагувати $service"
		  ((index++))
		done
        ;;
	  cat)
	    local index=1
	    for service in "${services[@]}"; do
		  echo -e "${BOLD}$index Сервіс $service:${NC}"
		  systemctl cat "$service" || log_error "Не вдалося показати юніт-файлу $service"
		  ((index++))
		done
        ;;
	  show)
	    local index=1
	    for service in "${services[@]}"; do
		  echo -e "\n${BOLD}$index Сервіс $service:${NC}"
		  systemctl show "$service" || log_error "Не вдалося показати всі параметри юніта $service"
		  ((index++))
		done
        ;;
	  list_dependencies)
	    local index=1
	    for service in "${services[@]}"; do
		  echo -e "${BOLD}$index Сервіс $service:${NC}"
		  systemctl list-dependencies "$service" || log_error "Не вдалося показати залежності $service"
		  ((index++))
		done
        ;;
	  list_unit_files)
	    local index=1
	    for service in "${services[@]}"; do
		  echo -e "${BOLD}$index Сервіс $service:${NC}"
		  systemctl list-unit-files "$service" || log_error "Не вдалося показати список юніт-файлів $service"
		  ((index++))
		done
        ;;
	  help)
	    local index=1
	    for service in "${services[@]}"; do
		  echo -e "${BOLD}$index Сервіс $service:${NC}"
		  systemctl help "$service" || log_error "Не вдалося показати довідку $service"
		  ((index++))
		done
        ;;
	  priority)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  priority="$(get_service_priority "$service")"
		  
		  printf "%-4s %-40s %s\n" "$index" "$service" "$priority"
		  
		  ((index++))
		done
	    ;;
	  short_description)
	    local index=1
	    for service in "${services[@]}"; do
		  
		  description="$(get_service_description "$service")"
		  
		  printf "%-4s %-40s - %s\n" "$index" "$service" "$description"
		  
		  ((index++))
		done
	    ;;
      *)
        echo "${RED}✖ Невідома дія: $action${NC}"
        ;;
	esac
  
  done
}

function show_service_filter_menu() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}"
    echo "Усі"
    echo "1) Активні"
    echo "2) Обов'язкові"
    echo "3) Опціональні"
    echo "4) Додадкові"
	echo "s) Шукати за назвою"
    menu_nav
}

function parse_service_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
            1) FILTER+=("active") ;;
            2) FILTER+=("required") ;;
            3) FILTER+=("optional") ;;
            4) FILTER+=("extra") ;;
            s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_service_action_menu() {
	menu_header "🛠️  Керування сервісами"
	echo "1) Переглянути стан (status)"
	echo "2) Запустити (start)"
	echo "3) Зупинити (stop)"
	echo "4) Перезапустити (restart)"
	echo "5) Перезавантажити конфігурацію (reload)"
    echo "6) Блокувати (mask)"
	echo "7) Розблокувати (unmask)"
	menu_header "🚀  Керування автозапуском сервісів"
	echo "11) Увімкнути автозапуск (enable)"
	echo "12) Вимкнути автозапуск (disable)"
	menu_header "📝  Робота з конфігураціями сервісів"
	echo "21) Редагувати override-конфіг (edit)"
	echo "22) Показати юніт-файл (cat)"
	menu_header "📊  Інформація та діагностика"
	echo "31) Перевірити активність (is-active)"
	echo "32) Перевірити автозапуск (is-enabled)"
	echo "33) Перевірити пріоритет"
	echo "34) Показати короткий опис"
	echo "35) Показати всі параметри юніта (show)"
	echo "36) Показати залежності (list-dependencies)"
	echo "37) Список юніт-файлів та їх стан (list-unit-files)"
	echo "h) Довідка (help)"
	menu_nav
}

function parse_service_action_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Нічого не вибрано"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) ACTION+=("status") ;;
			2) ACTION+=("start") ;;
			3) ACTION+=("stop") ;;
            4) ACTION+=("restart") ;;
			5) ACTION+=("reload") ;;
			6) ACTION+=("mask") ;;
			7) ACTION+=("unmask") ;;
            12) ACTION+=("enable") ;;
            13) ACTION+=("disable") ;;
			21) ACTION+=("edit") ;;
			22) ACTION+=("cat") ;;
			31) ACTION+=("is_active") ;;
			32) ACTION+=("is_enabled") ;;
			33) ACTION+=("priority") ;;
			34) ACTION+=("short_description") ;;
			35) ACTION+=("show") ;;
			36) ACTION+=("list_dependencies") ;;
			37) ACTION+=("list_unit_files") ;;
			h) ACTION+=("help") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function service_filter_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[all]="Усі"
		[active]="Активні"
		[required]="Обов'язкові"
		[optional]="Опціональні"
		[extra]="Додадкові"
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

function service_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[status]="Переглянути стан (status)"
		[start]="Запустити (start)"
		[stop]="Зупинити (stop)"
		[restart]="Перезапустити (restart)"
		[reload]="Перезавантажити конфігурацію (reload)"
		[mask]="Блокувати (mask)"
		[unmask]="Розблокувати (unmask)"
		[enable]="Увімкнути автозапуск (enable)"
		[disable]="Вимкнути автозапуск (disable)"
		[edit]="Редагувати override-конфіг (edit)"
		[cat]="Показати юніт-файл (cat)"
		[is_active]="Перевірити активність (is-active)"
		[is_enabled]="Перевірити автозапуск (is-enabled)"
		[priority]="Перевірити пріоритет"
		[short_description]="Показати короткий опис"
		[show]="Показати всі параметри юніта (show)"
		[list_dependencies]="Показати залежності (list-dependencies)"
		[list_unit_files]="Список юніт-файлів та їх стан (list-unit-files)"
		[help]="Довідка (help)"
	)
	
	Items=(
        status
		start
		stop
        restart
		reload
		mask
		unmask
        enable
        disable
		edit
		cat
		is_active
		is_enabled
		priority
		short_description
		show
		list_dependencies
		list_unit_files
		help
	)
}
