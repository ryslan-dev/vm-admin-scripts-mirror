declare -gA package_labels=(
  [get_components]='Отримуємо пакети'
  [no_components_found]='Не знайдено пакети'
  [no_components_found_with_filter]='Не знайдено пакети з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступний пакет'
  [available_components]='Доступні пакети'
  [no_components_selected]='Пакети не вибрані'
  [selected_component]='Обраний пакет'
  [selected_components]='Обрані пакети'
  [component_processing]='Обробка пакета'
  [components_processing]='Обробка пакетів'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраним пакетом?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними пакетами?'
)

# ===================== CACHE-DATA =====================

# Priorities cache
CACHE_FILE="${HOME}/.cache/package_priorities.cache"

# 🔄 Завантажуємо кеш priorities у асоціативний масив
function load_package_priorities_cache() {
  [[ -f "$CACHE_FILE" ]] || return 0
  
  if ! declare -p PACKAGE_PRIORITY &>/dev/null 2>&1; then
	declare -gA PACKAGE_PRIORITY
  fi
  
  local pkg priority

  while IFS='=' read -r pkg priority; do
    [[ -n "$pkg" && -n "$priority" ]] && PACKAGE_PRIORITY["$pkg"]="$priority"
  done < "$CACHE_FILE"
}

# Завантажуємо кеш priorities у пам’ять один раз на старті
#load_package_priorities_cache

# 💾 Запис priority у файл кешу
function save_package_priority_to_cache() {
  local pkg="$1"
  local priority="$2"
  echo "${pkg}=${priority}" >> "$CACHE_FILE"
}

# Descriptions cache
CACHE_FILE_2="${HOME}/.cache/package_descriptions.cache"

declare -A PACKAGE_DESCRIPTION

# 📥 Завантаження кешу
function load_package_descriptions_cache() {
    [[ -f "$CACHE_FILE_2" ]] || { 
        mkdir -p "${HOME}/.cache"
        : > "$CACHE_FILE_2"
        echo "(i) Файл кешу описів створено: $CACHE_FILE_2"
        return 0
    }
	
	if ! declare -p PACKAGE_DESCRIPTION &>/dev/null 2>&1; then
		declare -gA PACKAGE_DESCRIPTION
	fi
	
	local pkg description

    local count=0
    while IFS='=' read -r pkg description; do
        pkg="${pkg//[$'\t\r\n']/}"             # прибираємо таби/переноси
        description="${description//[$'\t\r\n']/}"
        [[ -z "$pkg" || -z "$description" ]] && continue
        PACKAGE_DESCRIPTION["$pkg"]="$description"
        ((count++))
    done < "$CACHE_FILE_2"

    echo "(i) Завантажено описів пакетів з кешу: $count"
}

# 💾 Збереження в кеш
function save_package_description_to_cache() {
    local pkg="$1"
    local description="$2"

    # Прибираємо пробіли на початку/в кінці
    pkg="$(echo -n "$pkg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    description="$(echo -n "$description" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Замінюємо нові рядки на пробіли
    description="$(echo "$description" | tr '\n' ' ' | tr -s ' ')"

    [[ -z "$pkg" || -z "$description" ]] && {
        echo "⚠️  Пропущено збереження: порожнє значення"
        return 1
    }

    mkdir -p "${HOME}/.cache"
    echo "${pkg}=${description}" >> "$CACHE_FILE_2"
}

# ===================== FUNCTIONS =====================

function is_pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# 🔍 Отримати пріоритет пакета
function show_package_priority() {
    local pkg="$1"
    local apt_priority=""
    local priority=""

    # Очищуємо pkg від пробілів
    pkg="$(echo "$pkg" | xargs)"
    [[ -z "$pkg" ]] && echo "unknown" && return 1

    # Створюємо глобальний асоціативний масив, якщо його ще немає
    if ! declare -p PACKAGE_PRIORITY &>/dev/null; then
        declare -gA PACKAGE_PRIORITY
        load_package_priorities_cache
    fi

    # Якщо є в кеші, беремо звідти
    if [[ -v PACKAGE_PRIORITY["$pkg"] ]]; then
        apt_priority="${PACKAGE_PRIORITY["$pkg"]}"
    else
        # Отримуємо Priority через apt-cache, лише один раз
        # Використовуємо grep + cut замість awk, щоб уникнути сабшелів у awk
        apt_priority="$(apt-cache show "$pkg" 2>/dev/null | grep -m1 '^Priority:' | cut -d' ' -f2-)"
        apt_priority="${apt_priority:-unknown}"

        # Зберігаємо у глобальний масив і кеш
        PACKAGE_PRIORITY["$pkg"]="$apt_priority"
        save_package_priority_to_cache "$pkg" "$apt_priority"
    fi

    # Встановлюємо внутрішню категорію пріоритету
    priority="${COMPONENT_PRIORITIES[$apt_priority]:-unknown}"

    echo "$priority"
}

function get_package_priority() {
    local pkg="$1"
    local result="$2"  # ім'я змінної для збереження
    local apt_priority=""
	local priority=""

    if ! declare -p PACKAGE_PRIORITY &>/dev/null; then
        declare -gA PACKAGE_PRIORITY
        load_package_priorities_cache
    fi

    if [[ -v PACKAGE_PRIORITY["$pkg"] ]]; then
        apt_priority="${PACKAGE_PRIORITY["$pkg"]}"
    else
		apt_priority=$(apt-cache show "$pkg" 2>/dev/null | awk -F': ' '/^Priority:/ { print $2; exit }')
        apt_priority="${apt_priority:-unknown}"
        PACKAGE_PRIORITY["$pkg"]="$apt_priority"
        save_package_priority_to_cache "$pkg" "$apt_priority"
    fi

    # Визначаємо внутрішній пріоритет
    priority="${COMPONENT_PRIORITIES[$apt_priority]:-unknown}"

    # Записуємо у змінну напряму, без echo
    printf -v "$result" "%s" "$priority"
}

function get_package_priorities() {
    local -n pkgs="$1"
	local -n result="$2"

    # Якщо масив порожній — вихід
    (( ${#pkgs[@]} == 0 )) && return 1

    # Використовуємо один виклик apt-cache show для всіх пакетів
    local pkg pri
    while IFS=: read -r pkg pri; do
        pkg="$(echo "$pkg" | xargs)"   # обрізаємо пробіли
        pri="${pri:-unknown}"
        result["$pkg"]="$pri"
    done < <(apt-cache show "${pkgs[@]}" 2>/dev/null | awk -v OFS=":" '
        /^Package:/ { pkg=$2 }
        /^Priority:/ { pri=$2; print pkg, pri }
    ')
}

function get_package_description() {
  local pkg="$1"
  local description
  
  # Якщо є в кеші
  if [[ -n "${PACKAGE_DESCRIPTIONS[$pkg]+_}" ]]; then
    description="${PACKAGE_DESCRIPTIONS[$pkg]}"
  elif [[ -n "${PACKAGE_DESCRIPTION[$pkg]+_}" ]]; then
    description="${PACKAGE_DESCRIPTION[$pkg]}"
  else
	# Інакше — отримаємо через apt show
    description=$(apt show "$pkg" 2>/dev/null | grep -m1 ^Description: | cut -d' ' -f2-)
	
    PACKAGE_DESCRIPTION["$pkg"]="$description"
	save_package_description_to_cache "$pkg" "$description"
  fi
  
  echo "$description"
}

function get_package_components() {
  local -n filters="$1"
  local -n _out=$2
  _out=()
  
  local PACKAGES=()
  local pkg_priority
  local -A priorities=()
  
  for f in "${filters[@]}"; do
    if [[ -v COMPONENT_PRIORITY["$f"] ]]; then
		priorities["$f"]=1
	fi
  done
  
  # 🔎 Отримуємо список пакетів
  if in_array "active" filters; then
	if [[ -z "$SEARCH" ]]; then
	  readarray -t PACKAGES < <(dpkg-query -W -f='${Package}\n')
	else
	  readarray -t PACKAGES < <(dpkg-query -W -f='${Package}\n' | grep -Fi "$SEARCH")
	fi
  else
    if [[ -z "$SEARCH" ]]; then
	  readarray -t PACKAGES < <(apt list 2>/dev/null | cut -d/ -f1 | tail -n +2)
	else
	  readarray -t PACKAGES < <(apt list *"$SEARCH"* 2>/dev/null | cut -d/ -f1 | tail -n +2)
	  #readarray -t PACKAGES < <(apt-cache search --names-only "$SEARCH" | awk '{print $1}')
	fi
  fi
  
  # Якщо немає фільтрів пріоритетів — просто віддаємо весь список без циклів
  if is_array_empty priorities; then
    _out=("${PACKAGES[@]}")
    return 0
  fi
  
  local -A pkg_riorities
  get_package_priorities PACKAGES pkg_riorities
  
  # Інакше — фільтруємо за пріоритетом
  for pkg in "${PACKAGES[@]}"; do
    #echo "$pkg:"
	#show_package_priority "$pkg"
	#pkg_priority="$(show_package_priority "$pkg")"
	#read -r pkg_priority <<< "$(get_package_priority "$pkg")"
	#get_package_priority "$pkg" pkg_priority
	pkg_priority="${pkg_riorities[$pkg]}"
	#echo "$pkg: $pkg_priority"
    if [[ -v priorities["$pkg_priority"] ]]; then
        _out+=("$pkg")
    fi
  done
}

function print_packages() {
  local -n arr=$1
  
  local priority description status
  
  local index=1
  for pkg in "${arr[@]}"; do
	
	priority=""
	description=""
	status=""
	
	get_package_priority "$pkg" priority
	description="$(get_package_description "$pkg")"
	
	status="not installed"
	if is_pkg_installed "$pkg"; then
		status="installed"
	fi
	
    printf "%-4s %-40s | %-13s | %-8s | %s\n" "$index" "$pkg" "$status" "$priority" "$description"
	((index++))
  done
}

function action_package_components() {
  local -n actions="$1"
  local -n packages="$2"
  local label pkg value
  
  local -A action_names=(
    [update]="Оновлення списку пакетів"
    [upgrade]="Оновлення встановлених пакетів"
    [full_upgrade]="Повне оновлення (з видаленням/заміною пакетів)"
	[dist_upgrade]="Повне оновлення (з видаленням/заміною пакетів)"
    [install]="Встановлення пакетів"
    [reinstall]="Перевстановлення пакетів"
    [remove]="Видалення пакетів (залишаючи конфіги)"
    [purge]="Видалення пакетів з очищенням конфігів"
    [autoremove]="Видалення неактивних залежностей"
    [search]="Пошук пакетів за назвою і описом"
    [show]="Інформація про пакет"
    [list]="Список пакетів"
    [policy]="Інформація про версії та репозиторії"
    [clean]="Повне очищення кешу"
    [autoclean]="Очищення застарілого кешу"
    [download]="Завантаження .deb файлу пакета без встановлення"
	[is_installed]="Перевірка активності пакетів"
	[priority]="Перевірка пріоритету пакетів"
	[short_description]="Вивід коротких описів"
  )
  
  action_package_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    
	text="${text//\{pkg\}/${pkg:-}}"
    echo "$text"
  }
  
  local priority
  local autoremove=0
  
  is_array_empty packages && log_warn "Пакети не вказані" && return 2
  is_array_empty actions && log_warn "Дії не вказані" && return 2

  for action in "${actions[@]}"; do
	
	pkg="${packages[0]:-}"
	if is_array_single packages && array_key_has_value "${action}_single" action_names; then
		label=$(action_package_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_package_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
      install)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  if is_pkg_installed "$pkg"; then
		    status="$(get_log_warn "$pkg уже встановлено")"
		  else 
            apt-get install -y "$pkg" && status="$(get_log_success "$pkg встановлено")" || status="$(get_log_error "Не вдалося встановити $pkg")"
		  fi
		  
		  printf "%-4s %-40s %s\n" "$index" "$pkg" "$status"
		  
		  ((index++))
		done
        ;;
      reinstall)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  apt-get install --reinstall -y "$pkg" && status="$(get_log_success "$pkg перевстановлено")" || status="$(get_log_error "Не вдалося перевстановити $pkg")"
		  
		  printf "%-4s %-40s %s\n" "$index" "$pkg" "$status"
		  
		  ((index++))
		done
        ;;
      remove)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  if is_pkg_installed "$pkg"; then
			get_package_priority "$pkg" priority
			if is_required "$pkg" "$priority"; then
			  status="$(get_log_warn "$pkg не видалено, бо є обов'язковим для роботи системи")"
			else
			  if is_pkg_installed "$pkg"; then
			    apt-get remove -y "$pkg" && status="$(get_log_success "$pkg видалено")" || status="$(get_log_error "Не вдалося видалити $pkg")"
		      else
			    status="$(get_log_warn "$pkg не встановлено")"
		      fi
		    fi
		  else
		    status="$(get_log_warn "$pkg не встановлено")"
          fi
	  
		  printf "%-4s %-40s %s\n" "$index" "$pkg" "$status"
		  
		  ((index++))
		done
        ;;
      purge)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  if is_pkg_installed "$pkg"; then
			get_package_priority "$pkg" priority
			if is_required "$pkg" "$priority"; then
		      status="$(get_log_warn "$pkg не видалено, бо є обов'язковим для роботи системи")"
		    else
			  apt-get -qq purge -y "$pkg" && {
                autoremove=1
                status="$(get_log_success "$pkg видалено")"
			  } || status="$(get_log_error "Не вдалося видалити $pkg")"
		    fi
		  else
		    status="$(get_log_warn "$pkg не встановлено")"
          fi
		  
		  printf "%-4s %-40s %s\n" "$index" "$pkg" "$status"
		  
		  ((index++))
		done
        ;;
	  autoremove)
		autoremove=1
		;;
	  is_installed)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  if is_pkg_installed "$pkg"; then
			status="installed"
		  else
			status="not installed"
		  fi
		  
		  printf "%-4s %-40s %s\n" "$index" "$pkg" "$status"
		  
		  ((index++))
		done
	    ;;
	  priority)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  get_package_priority "$pkg" priority
		  
		  printf "%-4s %-40s %s\n" "$index" "$pkg" "$priority"
		  
		  ((index++))
		done
	    ;;
	  short_description)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  description="$(get_package_description "$pkg")"
		  
		  printf "%-4s %-40s - %s\n" "$index" "$pkg" "$description"
		  
		  ((index++))
		done
	    ;;
	  show)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  echo -e "\n${BOLD}$index Пакет $pkg:${NC}"
		  apt show "$pkg" || log_error "Не вдалося показати інформацію про пакет $pkg"
		  ((index++))
		done
	    ;;
	  policy)
	    local index=1
		for pkg in "${packages[@]}"; do
		  echo -e "\n${BOLD}$index Пакет $pkg:${NC}"
		  apt policy "$pkg" || log_error "Не вдалося показати інформацію про версії та репозиторії для пакету $pkg"
		  ((index++))
		done
	    ;;
	  clean)
	    apt clean && log_success "Повне очищення кешу виконано" || log_error "Не вдалося виконати повне очищення кешу"
	    ;;
	  autoclean)
	    apt autoclean && log_success "Очищення застарілого кешу виконано" || log_error "Не вдалося виконати очищення застарілого кешу"
	    ;;
	  download)
	    local index=1
	    for pkg in "${packages[@]}"; do
		  
		  apt download "$pkg" && status="$(get_log_success ".deb файл пакета $pkg завантажено")" || status="$(get_log_error "Не вдалося завантажити .deb файл пакета $pkg")"
		  
		  printf "%-4s %-40s %s\n" "$index" "$pkg" "$status"
		  
		  ((index++))
		done
	    ;;
	  update)
	    apt update && log_success "Оновлення списку пакетів виконано" || log_error "Не вдалося виконати оновлення списку пакетів"
	    ;;
	  upgrade)
	    apt upgrade && log_success "Оновлення встановлених пакетів виконано" || log_error "Не вдалося виконати оновлення встановлених пакетів"
	    ;;
	  full_upgrade|dist_upgrade)
	    apt full-upgrade && log_success "Повне оновлення встановлених пакетів виконано" || log_error "Не вдалося виконати повне оновлення встановлених пакетів"
	    ;;
      *)
        log_error "Невідома дія: $action"
        ;;
	esac
  done
  
  if [[ "$autoremove" == 1 ]]; then
    echo
    echo -e "${YELLOW}⏳ ${action_names[autoremove]}...${NC}"
    apt autoremove -y && log_success "🧹 Команда autoremove виконана" || log_error "Не вдалося виконати autoremove"
  fi
}

function show_package_filter_menu() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}:"
    echo "Усі"
    echo "1) Встановлені"
    echo "2) Обов'язкові"
    echo "3) Опціональні"
    echo "4) Додадкові"
	echo "s) Шукати за назвою"
	menu_nav
}

function parse_package_filter_choices() {
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

function show_package_action_menu() {
	menu_header "🛠️  Керування пакетами:"
    echo "1) Встановити (install)"
	echo "2) Перевстановити (reinstall)"
	echo "3) Видалити (remove)"
	echo "4) Видалити і очистити (purge)"
	echo "5) Видалити неактивні залежності (autoremove)"
	menu_header "📊  Інформація та діагностика:"
	echo "21) Перевірити активність"
	echo "22) Перевірити пріоритет"
	echo "23) Показати короткий опис"
	echo "24) Показати інформацію про пакет (show)"
	echo "25) Показати версії та репозиторій (policy)"
	menu_header "🧹  Керування кешем пакетів:"
	echo "31) Видалити весь кеш завантажених .deb файлів (clean)"
	echo "32) Видалити застарілі .deb файли (autoclean)"
	echo "33) Завантажити .deb файл пакету без встановлення (download)"
	menu_header "🔄  Оновлення системи:"
	echo "41) Оновити список пакетів (update)"
	echo "42) Оновити встановлені пакети (upgrade)"
	echo "43) Оновити встановлені пакети повністю (full-upgrade)"
	menu_nav
}

function parse_package_action_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Нічого не вибрано"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) ACTION+=("install") ;;
            2) ACTION+=("reinstall") ;;
            3) ACTION+=("remove") ;;
            4) ACTION+=("purge") ;;
			5) ACTION+=("autoremove") ;;
			21) ACTION+=("is_installed") ;;
			22) ACTION+=("priority") ;;
			23) ACTION+=("short_description") ;;
			24) ACTION+=("show") ;;
			25) ACTION+=("policy") ;;
			31) ACTION+=("clean") ;;
			32) ACTION+=("autoclean") ;;
			33) ACTION+=("download") ;;
			41) ACTION+=("update") ;;
			42) ACTION+=("upgrade") ;;
			43) ACTION+=("full_upgrade") ;;
            c) return 1 ;;
            x) exit 0 ;;
			*) log_error "Некоректний вибір"; return 2 ;;
		esac
	done
}

function package_filter_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[all]="Усі"
		[active]="Встановлені"
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

function package_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[install]="Встановити (install)"
		[reinstall]="Перевстановити (reinstall)"
		[remove]="Видалити (remove)"
		[purge]="Видалити і очистити (purge)"
		[autoremove]="Видалити неактивні залежності (autoremove)"
		[is_installed]="Перевірити активність"
		[priority]="Перевірити пріоритет"
		[short_description]="Показати короткий опис"
		[show]="Показати інформацію про пакет (show)"
		[policy]="Показати версії та репозиторій (policy)"
		[clean]="Видалити весь кеш завантажених .deb файлів (clean)"
		[autoclean]="Видалити застарілі .deb файли (autoclean)"
		[download]="Завантажити .deb файл пакету без встановлення (download)"
		[update]="Оновити список пакетів (update)"
		[upgrade]="Оновити встановлені пакети (upgrade)"
		[full_upgrade]="Оновити встановлені пакети повністю (full-upgrade)"
	)
	
	Items=(
		install
		reinstall
		remove
		purge
		autoremove
		is_installed
		priority
		short_description
		show
		policy
		clean
		autoclean
		download
		update
		upgrade
		full_upgrade
	)
}
