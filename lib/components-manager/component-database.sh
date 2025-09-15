# ===================== LABELS =====================

declare -gA db_types=(
  [mysql]='mysql'
  [mariadb]='mariadb'
  [mysql_mariadb]='mysql'
  [postgresql]='postgresql'
  [sqlite]='sqlite'
  [mysqluser]='mysql'
  [mariadbuser]='mariadb'
  [postgresqluser]='postgresql'
  [sqliteuser]='sqlite'
)

declare -gA db_type_labels=(
  [mysql]='MySQL'
  [mariadb]='MariaDB'
  [mysql_mariadb]='MySQL / MariaDB'
  [postgresql]='PostgreSQL'
  [sqlite]='SQLite'
)

declare -gA database_labels=(
  [get_components]='Отримуємо бази даних'
  [no_components_found]='Не знайдено жодної бази даних'
  [no_components_found_with_filter]='Не знайдено жодної бази даних з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступна база даних'
  [available_components]='Доступні бази даних'
  [no_components_selected]='Бази даних не вибрані'
  [selected_component]='Обрана база даних'
  [selected_components]='Обрані бази даних'
  [component_processing]='Обробка бази даних'
  [components_processing]='Обробка баз даних'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраною базою даних?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними базами даних?'
)

declare -gA dbuser_labels=(
  [get_components]='Отримуємо БД-користувачі'
  [no_components_found]='Не знайдено жодного БД-користувача'
  [no_components_found_with_filter]='Не знайдено жодного БД-користувача з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступний БД-користувач'
  [available_components]='Доступні БД-користувачі'
  [no_components_selected]='БД-користувачі не вибрані'
  [selected_component]='Обраний БД-користувач'
  [selected_components]='Обрані БД-користувачі'
  [component_processing]='Обробка БД-користувача'
  [components_processing]='Обробка БД-користувачів'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраним БД-користувачем?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними БД-користувачами?'
)

declare -gA mysql_labels=()
for key in "${!database_labels[@]}"; do
    mysql_labels["$key"]="${database_labels[$key]}"
done

declare -gA mysqluser_labels=()
for key in "${!dbuser_labels[@]}"; do
    mysqluser_labels["$key"]="${dbuser_labels[$key]}"
done

declare -gA postgresqluser_labels=()
for key in "${!dbuser_labels[@]}"; do
    postgresqluser_labels["$key"]="${dbuser_labels[$key]}"
done

declare -gA sqliteuser_labels=()
for key in "${!dbuser_labels[@]}"; do
    sqliteuser_labels["$key"]="${dbuser_labels[$key]}"
done

# ===================== FUNCTIONS =====================

# get_mysql_databases [filters="..."] [mode=union|intersect] [search=regex]
#
# Іменовані аргументи (усі опціональні):
# search='regex'          — пошук за ключовими символами
# filters=f1,f2.... 	  — фільтри
# mode: union — повертає об’єднання (за замовчуванням), intersect — повертає лише ті БД, які одночасно підходять під усі фільтри
# output=lines|array      — формат виводу (в рядки або в масив), дефолт lines
# outvar=NAME             — ім’я масиву для output=array
# Повертає:0 — успіх; друкує список БД або наповнює масив outvar, 1/2 — помилка (деталі в stderr)
# login_path=NAME         — mysql --login-path=NAME (рекомендовано)
# defaults_file=/path.cnf — mysql --defaults-file=...
# socket=/path.sock       — шлях до сокета (якщо root через unix_socket)
# host=... user=... password=...  — TCP-підключення (НЕ бажано передавати пароль у CLI)
function get_mysql_databases() {
    local filters="all" search="" login_path="" mode="union"
    local output="lines" outvar=""
    local defaults_file="" socket="" host="" user="" password=""

    for arg in "$@"; do
        case "$arg" in
            filters=*) filters="${arg#*=}" ;;
            search=*)  search="${arg#*=}" ;;
            login_path=*) login_path="${arg#*=}" ;;
            defaults_file=*) defaults_file="${arg#*=}" ;;
            socket=*) socket="${arg#*=}" ;;
            host=*) host="${arg#*=}" ;;
            user=*) user="${arg#*=}" ;;
            password=*) password="${arg#*=}" ;;
            mode=*)    mode="${arg#*=}" ;;
            output=*)  output="${arg#*=}" ;;
            outvar=*)  outvar="${arg#*=}" ;;
        esac
    done

    local -a mysql_args=( -N -B --silent )
    if [[ -n "$login_path" ]]; then
        mysql_args+=( --login-path="$login_path" )
    elif [[ -n "$defaults_file" && -r "$defaults_file" ]]; then
        mysql_args+=( --defaults-file="$defaults_file" )
    elif [[ -n "$socket" || -S /var/run/mysqld/mysqld.sock ]]; then
        [[ -z "$socket" ]] && socket=/var/run/mysqld/mysqld.sock
        mysql_args+=( --protocol=socket -S "$socket" -u root )
    else
        [[ -n "$host" ]] && mysql_args+=( -h "$host" )
        [[ -n "$user" ]] && mysql_args+=( -u "$user" )
        [[ -n "$password" ]] && mysql_args+=( -p"$password" )
    fi
	
	[[ -z "$filters" ]] && filters="all"

    local IFS=','; read -ra flist <<< "$filters"; IFS=$' \t\n'

    local -a result=()
    local first=1

    for f in "${flist[@]}"; do
        local -a current=()
        case "$f" in
            all)
                local sql="SELECT SCHEMA_NAME FROM information_schema.SCHEMATA"
                sql+=" ORDER BY SCHEMA_NAME;"
                mapfile -t current < <(mysql "${mysql_args[@]}" -e "$sql") ;;
            local)
                mapfile -t current < <(mysql "${mysql_args[@]}" -e "
                  SELECT SCHEMA_NAME FROM information_schema.SCHEMATA
                  WHERE SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys','phpmyadmin','ftpserver','webpanel')
                  ORDER BY SCHEMA_NAME;") ;;
            system|required)
                current=(mysql information_schema performance_schema sys phpmyadmin ftpserver webpanel) ;;
            root)
                mapfile -t current < <(mysql "${mysql_args[@]}" -e "
                  SELECT DISTINCT Db FROM mysql.db WHERE User='root' ORDER BY Db;") ;;
            orphan)
                mapfile -t current < <(mysql "${mysql_args[@]}" -e "
                  SELECT SCHEMA_NAME 
                  FROM information_schema.SCHEMATA s
                  WHERE SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys')
                    AND NOT EXISTS (
                      SELECT 1 FROM mysql.db d WHERE d.Db = s.SCHEMA_NAME
                    )
                  ORDER BY SCHEMA_NAME;") ;;
            notempty)
                mapfile -t current < <(mysql "${mysql_args[@]}" -e "
                  SELECT DISTINCT TABLE_SCHEMA
                  FROM information_schema.TABLES
                  WHERE TABLE_SCHEMA NOT IN ('mysql','information_schema','performance_schema','sys')
                  ORDER BY TABLE_SCHEMA;") ;;
            empty)
                mapfile -t current < <(mysql "${mysql_args[@]}" -e "
                  SELECT SCHEMA_NAME
                  FROM information_schema.SCHEMATA s
                  WHERE SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys')
                    AND NOT EXISTS (
                      SELECT 1 FROM information_schema.TABLES t
                      WHERE t.TABLE_SCHEMA = s.SCHEMA_NAME
                    )
                  ORDER BY SCHEMA_NAME;") ;;
            webuser)
                local linux_users
                linux_users=$(getent group webusers | cut -d: -f4 | tr ',' '\n' | sort -u)
                for u in $linux_users; do
                    mysql "${mysql_args[@]}" -e "SELECT DISTINCT Db FROM mysql.db WHERE User='$u';"
                done | sort -u | mapfile -t current ;;
            admin)
                local sudo_users
                sudo_users=$(/usr/local/bin/get-sudo-users | awk '{print $1}')
                for u in $sudo_users; do
                    mysql "${mysql_args[@]}" -e "SELECT DISTINCT Db FROM mysql.db WHERE User='$u';"
                done | sort -u | mapfile -t current ;;
            search)
                local sql="SELECT SCHEMA_NAME FROM information_schema.SCHEMATA ORDER BY SCHEMA_NAME;"
                mapfile -t current < <(mysql "${mysql_args[@]}" -e "$sql" | grep -E "$search") ;;
            *)
                echo "ERR:get_mysql_databases: невідомий фільтр '$f'" >&2 ;;
        esac

        if (( first )); then
            result=("${current[@]}")
            first=0
        else
            if [[ "$mode" == "intersect" ]]; then
                mapfile -t result < <(printf '%s\n' "${result[@]}" "${current[@]}" | sort | uniq -d)
            else
                mapfile -t result < <(printf '%s\n' "${result[@]}" "${current[@]}" | sort -u)
            fi
        fi
    done

    if [[ "$output" == "array" ]]; then
        if [[ -z "$outvar" ]]; then
            echo "ERR:get_mysql_databases: потрібно задати outvar=NAME для output=array" >&2
            return 2
        fi
        local -n __outvar="$outvar"
        __outvar=("${result[@]}")
    else
        printf "%s\n" "${result[@]}"
    fi
}

# get_mysql_users [display=full|short] [filters="..."] [mode=union|intersect] [search=regex]
#
# Іменовані аргументи (усі опціональні):
# display=(full|short) 	  — показувати повну назву чи без @localhost
# search='regex'          — пошук за ключовими символами
# filters=f1,f2.... 	  — фільтри
# mode: union — повертає об’єднання (за замовчуванням), intersect — повертає лише ті БД, які одночасно підходять під усі фільтри
# output=lines|array      — формат виводу (в рядки або в масив), дефолт lines
# outvar=NAME             — ім’я масиву для output=array
# Повертає:0 — успіх; друкує список користувачів або наповнює масив outvar, 1/2 — помилка (деталі в stderr)
# login_path=NAME         — mysql --login-path=NAME
# defaults_file=/path.cnf — mysql --defaults-file=...
# socket=/path.sock       — шлях до сокета (якщо root через unix_socket)
# host=... user=... password=...  — TCP-підключення (НЕ бажано передавати пароль у CLI)
function get_mysql_users() {
    local filters="all" search="" login_path="" mode="union"
    local output="lines" outvar=""
    local defaults_file="" socket="" host="" user="" password=""
	local display="full"
	
    for arg in "$@"; do
        case "$arg" in
			display=*) display="${arg#*=}" ;;
            filters=*) filters="${arg#*=}" ;;
            search=*)  search="${arg#*=}" ;;
            login_path=*) login_path="${arg#*=}" ;;
            defaults_file=*) defaults_file="${arg#*=}" ;;
            socket=*) socket="${arg#*=}" ;;
            host=*) host="${arg#*=}" ;;
            user=*) user="${arg#*=}" ;;
            password=*) password="${arg#*=}" ;;
            mode=*)    mode="${arg#*=}" ;;
            output=*)  output="${arg#*=}" ;;
            outvar=*)  outvar="${arg#*=}" ;;
        esac
    done

    # базові аргументи mysql
    local -a mysql_args=( -N -B --silent )
    if [[ -n "$login_path" ]]; then
        mysql_args+=( --login-path="$login_path" )
    elif [[ -n "$defaults_file" && -r "$defaults_file" ]]; then
        mysql_args+=( --defaults-file="$defaults_file" )
    elif [[ -n "$socket" || -S /var/run/mysqld/mysqld.sock ]]; then
        [[ -z "$socket" ]] && socket=/var/run/mysqld/mysqld.sock
        mysql_args+=( --protocol=socket -S "$socket" -u root )
    else
        [[ -n "$host" ]] && mysql_args+=( -h "$host" )
        [[ -n "$user" ]] && mysql_args+=( -u "$user" )
        [[ -n "$password" ]] && mysql_args+=( -p"$password" )
    fi

    # отримуємо ВСІХ користувачів
    local -a ALLUSERS=()
    if ! mapfile -t ALLUSERS < <(mysql "${mysql_args[@]}" -e \
        "SELECT CONCAT(User,'@',Host) FROM mysql.user ORDER BY User,Host;" 2>/dev/null); then
        echo "ERR:get_mysql_users: не вдалося отримати список користувачів" >&2
        return 1
    fi
	
	[[ -z "$filters" ]] && filters="all"

    local IFS=','; read -ra flist <<< "$filters"; IFS=$' \t\n'
    local -a result=()
    local first=1

    for f in "${flist[@]}"; do
        local -a current=()
        case "$f" in
            all)
                current=("${ALLUSERS[@]}") ;;
            local)
                current=($(printf '%s\n' "${ALLUSERS[@]}" \
                    | grep -Ev '^(root|mysql|mysql\.sys|mysql\.session|mariadb\.sys|debian-sys-maint|phpmyadmin|webpaneladmin|dbserver|ftpserver|ftpuser|mailserver)@')) ;;
			system|required)
				current=($(printf '%s\n' "${ALLUSERS[@]}" \
					| grep -E '^(root|mysql|mysql\.sys|mysql\.session|mariadb\.sys|debian-sys-maint|phpmyadmin|webpaneladmin|dbserver|ftpserver|ftpuser|mailserver)@')) ;;
            root)
                current=($(printf '%s\n' "${ALLUSERS[@]}" | grep -E '^root@')) ;;
            webuser)
                local linux_users
                linux_users=$(getent group webusers | cut -d: -f4 | tr ',' '\n' | sort -u)
                for u in $linux_users; do
                    current+=($(printf '%s\n' "${ALLUSERS[@]}" | grep -E "^$u@"))
                done ;;
            admin)
                local sudo_users
                sudo_users=$(/usr/local/bin/get-sudo-users | awk '{print $1}')
                for u in $sudo_users; do
                    current+=($(printf '%s\n' "${ALLUSERS[@]}" | grep -E "^$u@"))
                done ;;
            notempty)
                mapfile -t current < <(
                  mysql "${mysql_args[@]}" -e \
                  "SELECT DISTINCT CONCAT(User,'@',Host) FROM mysql.db;"
                ) ;;
            empty)
                mapfile -t current < <(
                  mysql "${mysql_args[@]}" -e "
                  SELECT CONCAT(u.User,'@',u.Host)
                  FROM mysql.user u
                  WHERE NOT EXISTS (
                    SELECT 1 FROM mysql.db d
                    WHERE d.User=u.User AND d.Host=u.Host
                  );"
                ) ;;
            search)
                current=($(printf '%s\n' "${ALLUSERS[@]}" | grep -E "$search")) ;;
            *)
                echo "ERR:get_mysql_users: невідомий фільтр '$f'" >&2 ;;
        esac

        # union / intersect
        if (( first )); then
            result=("${current[@]}")
            first=0
        else
            if [[ "$mode" == "intersect" ]]; then
                mapfile -t result < <(printf '%s\n' "${result[@]}" "${current[@]}" | sort | uniq -d)
            else
                mapfile -t result < <(printf '%s\n' "${result[@]}" "${current[@]}" | sort -u)
            fi
        fi
    done
	
    if [[ "$display" == "short" ]]; then
        local -a transformed=()
        for u in "${result[@]}"; do
            case "$u" in
                *@localhost) transformed+=("${u%@*}") ;;   # обрізаємо @localhost
                *) transformed+=("$u") ;;                # інші лишаємо як є
            esac
        done
        result=("${transformed[@]}")
    fi

    if [[ "$output" == "array" ]]; then
        if [[ -z "$outvar" ]]; then
            echo "ERR:get_mysql_users: потрібно задати outvar=NAME для output=array" >&2
            return 2
        fi
        local -n __outvar="$outvar"
        __outvar=("${result[@]}")
    else
        printf "%s\n" "${result[@]}"
    fi
}

function get_mysql_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local Filters_str=$(IFS=','; echo "${Filters[*]}")
  
  get_mysql_databases filters="$Filters_str" output=array outvar=_out
}

function get_mysqluser_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local Filters_str=$(IFS=','; echo "${Filters[*]}")
  
  get_mysql_users filters="$Filters_str" output=array outvar=_out
}

function action_database_components() {
  local -n actions="$1"
  local -n databases="$2"
  local label db value
  local db_type="${db_types[$TYPE]:-$TYPE}"
  
  local -A action_names=(
    [add]="Створення бази даних {db_type}"
  )
  
  action_database_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    
	text="${text//\{db_type\}/${db_type_labels[$db_type]:-$db_type}}"
	text="${text//\{db\}/${db:-}}"
    echo "$text"
  }
  
  is_array_empty databases && log_warn "Бази даних не вказані" && return 2
  is_array_empty actions && log_warn "Дії не вказані" && return 2
  
  for action in "${actions[@]}"; do
	
	db="${databases[0]:-}"
	if is_array_single databases && array_key_has_value "${action}_single" action_names; then
		label=$(action_database_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_database_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
	  #add) add_database ;;
      *) log_error "Невідома дія: $action" ;;
	esac
  
  done
}

function action_dbuser_components() {
  local -n actions="$1"
  local -n users="$2"
  local label db user value
  local db_type="${db_types[$TYPE]:-$TYPE}"
  
  local -A action_names=(
    [add]="Створення БД-користувача {db_type}"
  )
  
  action_dbuser_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    
	text="${text//\{db_type\}/${db_type_labels[$db_type]:-$db_type}}"
	text="${text//\{db\}/${db:-}}"
	text="${text//\{user\}/${user:-}}"
    echo "$text"
  }
  
  is_array_empty users && log_warn "БД-користувачі не вказані" && return 2
  is_array_empty actions && log_warn "Дії не вказані" && return 2
  
  for action in "${actions[@]}"; do
	
	user="${users[0]:-}"
	if is_array_single users && array_key_has_value "${action}_single" action_names; then
		label=$(action_dbuser_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_dbuser_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
      *) log_error "Невідома дія: $action" ;;
	esac
  
  done
}

function action_mysql_components() {
	local -n _ACTIONS="$1"
	local -n _COMPONENTS="$2"
  
	action_database_components _ACTIONS _COMPONENTS
}

function action_mysqluser_components() {
	local -n _ACTIONS="$1"
	local -n _COMPONENTS="$2"
  
	action_dbuser_components _ACTIONS _COMPONENTS
}

function show_databases_menu_select() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}:"
    echo "1) Створити базу даних"
    echo "2) Бази даних MySQL"
	echo "3) Бази даних PostgreSQL"
	echo "4) Бази даних SQLite"
	echo "5) Бекапи баз даних"
	menu_header "‍🗃️👦  Користувачі баз даних:"
	echo "11) Додати нового БД-користувача"
	echo "12) Користувачі MySQL "
	echo "13) Користувачі PostgreSQL "
	echo "14) Користувачі SQLite "
	menu_nav
}

function parse_databases_menu_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Нічого не вибрано"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) SELECT+=("add_db") ;;
			2) SELECT+=("mysql_databases") ;;
			3) SELECT+=("postgresql_databases") ;;
			4) SELECT+=("sqlite_databases") ;;
			5) SELECT+=("db_backups") ;;
			11) SELECT+=("add_dbuser") ;;
			12) SELECT+=("mysql_users") ;;
			13) SELECT+=("postgresql_users") ;;
			14) SELECT+=("sqlite_users") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_database_action_menu() {
	menu_header "🛠️  Керування базами даних:"
    echo "1) Додати нову базу даних"
    echo "2) Видалити"
	menu_header "📊  Інформація та діагностика:"
	echo "21) Показати дані бази даних"
    echo "22) Показати інформацію про базу даних"
	echo "23) Перевірити ID"
	echo "24) Перевірити БД-користувачів"
	menu_nav
}

function parse_database_action_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Нічого не вибрано"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) ACTION+=("add") ;;
			2) ACTION+=("delete") ;;
			21) ACTION+=("data") ;;
			22) ACTION+=("info") ;;
			23) ACTION+=("id") ;;
			24) ACTION+=("dbusers") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_dbuser_action_menu() {
	menu_header "🛠️  Керування БД-користувачами:"
    echo "1) Додати нового БД-користувача"
    echo "2) Видалити"
	echo "3) Змінити пароль"
	menu_header "📊  Інформація та діагностика:"
	echo "21) Показати дані БД-користувача"
    echo "22) Показати інформацію про БД-користувача"
	echo "23) Перевірити ID"
	echo "24) Перевірити бази даних"
	menu_nav
}

function parse_dbuser_action_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Нічого не вибрано"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) ACTION+=("add") ;;
			2) ACTION+=("delete") ;;
			3) ACTION+=("passwd") ;;
			21) ACTION+=("data") ;;
			22) ACTION+=("info") ;;
			23) ACTION+=("id") ;;
			24) ACTION+=("databases") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_mysql_filter_menu() {
	menu_header "🗃️  Бази даних MySQL:"
    echo "Усі"
    echo "1) Локальні"
	echo "2) Системні"
	echo "3) Обов'язкові"
	echo "4) Root"
	echo "5) Веб-користувачів"
	echo "6) Адміністраторів"
	echo "7) Без користувачів"
	echo "8) Непорожні"
	echo "9) Порожні"
	echo "s) Шукати за назвою"
	menu_nav
}
function parse_mysql_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
            1) FILTER+=("local") ;;
			2) FILTER+=("system") ;;
			3) FILTER+=("required") ;;
			4) FILTER+=("root") ;;
			5) FILTER+=("webuser") ;;
            6) FILTER+=("admin") ;;
			7) FILTER+=("orphan") ;;
			8) FILTER+=("notempty") ;;
			9) FILTER+=("empty") ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_mysql_action_menu() {
	show_database_action_menu
}
function parse_mysql_action_choices() {
	parse_database_action_choices
}

function show_mysqluser_filter_menu() {
	menu_header "🗃️👦  Користувачі баз даних:"
    echo "Усі"
    echo "1) Локальні"
	echo "2) Системні"
	echo "3) Обов'язкові"
	echo "4) Root"
	echo "5) Веб-користувачів"
	echo "6) Адміністраторів"
	echo "7) З базами даних"
	echo "8) Без баз даних"
	echo "s) Шукати за назвою"
	menu_nav
}
function parse_mysqluser_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
            1) FILTER+=("local") ;;
			2) FILTER+=("system") ;;
			3) FILTER+=("required") ;;
			4) FILTER+=("root") ;;
			5) FILTER+=("webuser") ;;
            6) FILTER+=("admin") ;;
			7) FILTER+=("notempty") ;;
			8) FILTER+=("empty") ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_mysqluser_action_menu() {
	show_dbuser_action_menu
}
function parse_mysqluser_action_choices() {
	parse_dbuser_action_choices
}

function database_component_action() {
  local -n actions="$1"
  local label

  is_array_empty actions && log_warn "Нічого не вибрано" && return 2
  
  local -A action_names=(
    [add_mysql_db]="Створення бази даних"
  )
  
  database_component_action__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    echo "$text"
  }
  
  for action in "${actions[@]}"; do
	
	if array_key_has_value "$action" action_names; then
        label=$(database_component_action__get_label "$action")
		echo -e "\n${YELLOW_BOLD}$label${NC}\n"
    fi

	case "$action" in
		add_mysql_db)  ;;
		add_postgresql_db)  ;;
		add_sqlite_db)  ;;
		mysql_databases)
			local TYPE="mysql"
			component_menu
			;;
		postgresql_databases)  ;;
		sqlite_databases)  ;;
		db_backups)  ;;
		add_mysql_user)  ;;
		add_postgresql_user)  ;;
		add_sqlite_user)  ;;
		mysql_users)
			local TYPE="mysqluser"
			component_menu
			;;
		postgresql_users)  ;;
		sqlite_users)  ;;
	esac
  
  done
}

function database_component_menu(){
	component_type_menu
}

function database_select_menu_items(){

	local -n Items="$1"
	local -n Labels="$2"
	
	local menu_items=()
	local menu_parts=()
	local db_menu_items dbuser_menu_items

	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[db_menu]="Бази даних"
		[dbuser_menu]="БД Користувачі"
		[settings_menu]="Налаштування"
		[db_menu_header]="${HEADER_LABELS[$TYPE]:-$TYPE}"
		[dbuser_menu_header]="${HEADER_LABELS[dbuser]:-}"
		[add_db]="Створити базу даних"
		[mysql_databases]="Бази даних MySQL"
		[postgresql_databases]="Бази даних PostgreSQL"
		[sqlite_databases]="Бази даних SQLite"
		[db_backups]="Бекапи баз даних"
		[add_dbuser]="Додати нового БД-користувача"
		[mysql_users]="БД Користувачі MySQL "
		[postgresql_users]="БД Користувачі PostgreSQL "
		[sqlite_users]="БД Користувачі SQLite "
	)
	
	menu_parts=(
		db_menu
		dbuser_menu
	)
	
	db_menu_items=(
		add_db
		mysql_databases
		postgresql_databases
		sqlite_databases
		db_backups
	)
	
	dbuser_menu_items=(
		add_dbuser
		mysql_users
		postgresql_users
		sqlite_users
	)
	
	# menu choose
	if [[ "$MENU_CHOOSE_TYPE" == "menu_choose" ]]; then
	
		menu_items=("${db_menu_items[@]}")
		
		for key in "${menu_parts[@]}"; do
			[[ "$key" == "db_menu" ]] && continue
			menu_items+=("$key")
		done
		
		Items=("${menu_items[@]}")
		
	else
	
		menu_items=()
		if ! is_array_empty menu_parts; then
			for key in "${menu_parts[@]}"; do
				if array_isset "${key}_items"; then
					local -n menuarr="${key}_items"
					if ! is_array_empty menuarr; then
						if array_key_has_value "${key}_header" menu_labels; then
							menu_items+=("$key")
						fi
						local -n menuarr="${key}_items"
						for opt in "${menuarr[@]}"; do
							[[ -n "$opt" ]] && menu_items+=("$opt")
						done
					fi
				fi
			done
		fi
		menu_items+=("menu_nav")
		
		Items=("${menu_items[@]}")
	fi
}

function mysql_filter_menu_items(){

	local -n Items="$1"
	local -n Labels="$2"
	
	HEADER_LABELS[mysql]="$(array_get HEADER_LABELS database) MySQL"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[mysql_menu_header]="$(array_get HEADER_LABELS database) MySQL"
		[all]="Усі"
		[local]="Локальні"
		[system]="Системні"
		[required]="Обов'язкові"
		[root]="Root"
		[webuser]="Веб-користувачів"
		[admin]="Адміністраторів"
		[orphan]="Без користувачів"
		[notempty]="Непорожні"
		[empty]="Порожні"
		[search]="Шукати за назвою"
	)

	Items=(
		all
		local
		system
		required
		root
		webuser
        admin
		orphan
		notempty
		empty
		search
	)
}

function mysqluser_filter_menu_items(){

	local -n Items="$1"
	local -n Labels="$2"
	
	HEADER_LABELS[mysqluser]="$(array_get HEADER_LABELS dbuser) MySQL"

	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[mysqluser_menu_header]="$(array_get HEADER_LABELS dbuser) MySQL"
		[all]="Усі"
		[local]="Локальні"
		[system]="Системні"
		[required]="Обов'язкові"
		[root]="Root"
		[webuser]="Веб-користувачів"
		[admin]="Адміністраторів"
		[notempty]="З базами даних"
		[empty]="Без баз даних"
		[search]="Шукати за назвою"
	)

	Items=(
		all
        local
		system
		required
		root
		webuser
        admin
		notempty
		empty
		search
	)
}

function database_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[add]="Додати нову базу даних"
		[delete]="Видалити"
		[data]="Показати дані бази даних"
		[info]="Показати інформацію про базу даних"
		[id]="Перевірити ID"
		[dbusers]="Перевірити БД-користувачів"
	)
	
	Items=(
		add
		delete
		data
		info
		id
		dbusers
	)
}

function mysql_action_menu_items() {
    database_action_menu_items "$@"
}

function dbuser_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[add]="Додати нового БД-користувача"
		[delete]="Видалити"
		[passwd]="Змінити пароль"
		[data]="Показати дані БД-користувача"
		[info]="Показати інформацію про БД-користувача"
		[id]="Перевірити ID"
		[databases]="Перевірити бази даних"
	)
	
	Items=(
		add
		delete
		passwd
		data
		info
		id
		databases
	)
}

function mysqluser_action_menu_items() {
    dbuser_action_menu_items "$@"
}
