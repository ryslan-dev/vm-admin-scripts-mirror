# ===================== LABELS =====================

declare -gA user_labels=(
  [get_components]='Отримуємо користувачі'
  [no_components_found]='Не знайдено жодного користувача'
  [no_components_found_with_filter]='Не знайдено жодного користувача з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступний користувач'
  [available_components]='Доступні користувачі'
  [no_components_selected]='Користувачі не вибрані'
  [selected_component]='Обраний користувач'
  [selected_components]='Обрані користувачі'
  [component_processing]='Обробка користувача'
  [components_processing]='Обробка користувачів'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраним користувачем?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними користувачами?'
)

declare -gA localuser_labels=()
for key in "${!user_labels[@]}"; do
    localuser_labels["$key"]="${user_labels[$key]}"
done

declare -gA sysuser_labels=()
for key in "${!user_labels[@]}"; do
    sysuser_labels["$key"]="${user_labels[$key]}"
done

declare -gA group_labels=(
  [get_components]='Отримуємо групи'
  [no_components_found]='Не знайдено жодної групи'
  [no_components_found_with_filter]='Не знайдено жодної групи з фільтром: $(IFS=, ; echo "${FILTER[*]}")'
  [available_component]='Доступна група'
  [available_components]='Доступні групи'
  [no_components_selected]='Групи не вибрані'
  [selected_component]='Обрана група'
  [selected_components]='Обрані групи'
  [component_processing]='Обробка групи'
  [components_processing]='Обробка груп'
  [q_continue_working_with_selected_component]='Продовжити роботу з обраною групою?'
  [q_continue_working_with_selected_components]='Продовжити роботу з обраними групами?'
)

declare -gA user_passwd_statuses=(
	["P"]="активний"
	["L"]="заблокований"
	["NP"]="немає пароля"
	["LK"]="заблокований"
)
	
declare -gA user_shell_statuses=(
	["/bin/sh"]="доступний (мінімально)"
	["/usr/bin/sh"]="доступний (мінімально)"
	["/bin/bash"]="доступний (повноцінно)"
	["/usr/bin/bash"]="доступний (повноцінно)"
	["/bin/rbash"]="доступний (обмежений)"
	["/usr/bin/rbash"]="доступний (обмежений)"
	["/bin/dash"]="доступний (мінімально)"
	["/usr/bin/dash"]="доступний (мінімально)"
	["/usr/bin/screen"]="доступний (нестандартний, потрібен контекст)"
	["/usr/sbin/nologin"]="недоступний (вхід заборонено)"
	["/bin/false"]="недоступний (повністю блокує вхід)"
)
	
declare -gA user_shell_descriptions=(
	["/bin/sh"]="доступний (POSIX-совісна оболонка, мінімальний функціонал для скриптів)"
	["/usr/bin/sh"]="доступний (POSIX-совісна оболонка, мінімальний функціонал для скриптів)"
	["/bin/bash"]="доступний (Bash, повноцінна оболонка з автодоповненням і скриптами)"
	["/usr/bin/bash"]="доступний (Bash, повноцінна оболонка з автодоповненням і скриптами)"
	["/bin/rbash"]="доступний (restricted Bash, обмежує зміну каталогів і PATH, блокує деякі команди)"
	["/usr/bin/rbash"]="доступний (restricted Bash, обмежує зміну каталогів і PATH, блокує деякі команди)"
	["/bin/dash"]="доступний (швидка мінімальна оболонка, сумісна з POSIX, для скриптів)"
	["/usr/bin/dash"]="доступний (швидка мінімальна оболонка, сумісна з POSIX, для скриптів)"
	["/usr/bin/screen"]="доступний (інтерпретатор мультиплексора, не використовується як стандартна shell)"
	["/usr/sbin/nologin"]="недоступний (заблокований вхід, показує повідомлення про заборону)"
	["/bin/false"]="недоступний (завжди завершує сесію, повністю блокує логін)"
)

# ===================== FUNCTIONS =====================

# Перевірка існування користувача
function user_isset() {
    id "$1" &>/dev/null
}

# 🛡 Перевірка критичних користувачів
function is_required_user() {
    [[ "$1" =~ ^(root|nobody|daemon|bin|www-data|vmail|systemd-.*)$ ]]
}

function is_service_user() {
    local user="$1"
    local uid

    # root не є сервісним
    [[ "$user" == "root" ]] && return 1

    # systemd-* вважаємо сервісними
    [[ "$user" =~ ^systemd-.*$ ]] && return 0

    # отримуємо UID
    uid=$(id -u "$user")

    # користувачі з UID від 1 до 999 включно — сервісні
    if [[ "$uid" -gt 0 && "$uid" -lt 1000 ]]; then
        return 0
    fi

    return 1
}

# Перевірка блокування користувача
function is_unlocked_user(){
    local user="$1"

    if ! user_passwd_locked "$user" && ! user_shell_locked "$user"; then
        return 0
    else
        return 1
    fi
}

function is_locked_user(){
    local user="$1"

    if user_passwd_locked "$user" && user_shell_locked "$user"; then
        return 0
    else
        return 1
    fi
}

function user_passwd_locked(){
    local user="$1"
	local pass_status
    
	# Перевірка пароля
    pass_status=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')

    if [[ "$pass_status" == "L" || "$pass_status" == "LK" ]]; then
        return 0
    else
        return 1
    fi
}

function user_shell_locked(){
    local user="$1"
	local shell
    
    # Перевірка shell
    shell=$(getent passwd "$user" | cut -d: -f7)
	
    if user_shell_disabled "$user" && [[ -f "$backup_file" ]]; then
		return 0
    fi
	
	return 1
}

function user_shell_disabled(){
    local user="$1"
	local shell
    
    # Перевірка shell
    shell=$(getent passwd "$user" | cut -d: -f7)

    if [[ "$shell" =~ ^(/usr/sbin/nologin|/bin/false)$ ]]; then
        return 0
    else
        return 1
    fi
}

# Перевірка існування групи
function group_isset() {
	getent group "$1" >/dev/null
}

# 🛡 Перевірка критичних груп
function group_required() {
    [[ "$1" =~ ^(root|sudo|google-sudoers|adm|www-data|mail|vmail)$ ]]
}

function user_homedir(){
	local user="$1"
	getent passwd "$user" | cut -d: -f6
}

function user_shell(){
	local user="$1"
	getent passwd "$user" | cut -d: -f7
}

function user_groups(){
	local user="$1"
	id -nG "$user" | sed 's/ /, /g'
}

function user_info() {
    local user="$1"

    # ANSI-кольори
	local RED='\033[0;31m'       # темно-червоний
	local YELLOW='\033[0;33m'    # темно-жовтий
	local GREEN='\033[0;32m'     # темно-зелений
	local CYAN='\033[0;36m'      # темно-блакитний
	local BLUE='\033[0;34m'      # темно-синій
	local MAGENTA='\033[0;35m'   # темно-фіолетовий
	local WHITE='\033[0;37m'     # світло-сірий
	local NC='\033[0m'           # скидання кольору
	
	local LC="$LIGHT_GRAY"


    # Перевірка існування користувача
    if ! user_isset "$user"; then
        log_error "Користувача $user не знайдено"
        return 1
    fi

	# --- Отримуємо всю базову інформацію один раз ---
	local user_info id_info uid gid gids groups user_id group_id comment homedir shell
	user_info=$(getent passwd "$user" 2>/dev/null)
	id_info=$(id "$user" 2>/dev/null)
	passwd_status=$(passwd -S "$user" 2>/dev/null)
	
	uid=$(echo "$id_info" | awk -F '[=()]' '{print $2 " (" $3 ")"}')
	gid=$(echo "$id_info" | awk -F '[=()]' '{print $5 " (" $6 ")"}')
	gids=$(echo "$id_info" | awk -F 'groups=' '{print $2}' | sed 's/),/), /g; s/(/ (/g')
	groups=$(id -nG "$user" | sed 's/ /, /g')
	
	IFS=: read -r name _ user_id group_id comment homedir shell <<< "$user_info"
	
	IFS=' ' read -r _ passwd_status passwd_last_change passwd_min passwd_max passwd_warn passwd_inactive <<< "$passwd_status"

	local passwd_status_str="$passwd_status"
	[[ -n "${user_passwd_statuses[$passwd_status]:-}" ]] && passwd_status_str="$passwd_status - ${user_passwd_statuses[$passwd_status]}"
	
	local shell_str="$shell"
	[[ -n "${user_shell_statuses[$shell]:-}" ]] && shell_str="$shell - ${user_shell_statuses[$shell]}"
	
	local shell_dsc="$shell_str"
	[[ -n "${user_shell_descriptions[$shell]:-}" ]] && shell_dsc="$shell - ${user_shell_descriptions[$shell]}"
	
	# --- Основне ---
	echo -e "${LC}Ім’я:${NC} $name"
	echo -e "${LC}UID:${NC} $user_id"
	echo -e "${LC}GID:${NC} $group_id"
	echo -e "${LC}Домашня директорія:${NC} $homedir"
	echo -e "${LC}Групи:${NC} $groups"
	echo -e "${LC}Пароль:${NC} $passwd_status_str"
	echo -e "${LC}Shell:${NC} $shell_str"
	if [[ -n "${comment// }" ]]; then
    echo -e "${LC}Коментар:${NC} $comment"
	fi

	# --- ID ---
	echo -e "\n${CYAN}🆔  ID користувача, групи${NC}"
	echo -e "${LC}UID:${NC} $uid"
	echo -e "${LC}GID:${NC} $gid"
	echo -e "${LC}Групи:${NC} $gids"

	# --- Домашня директорія ---
	echo -e "\n${CYAN}🏠  Домашня директорія${NC}"
	homedir=$(eval echo "~$user")
	if [[ -d "$homedir" ]]; then
		echo -e "${LC}Шлях:${NC} $homedir"
		echo -e "${LC}Дата створення:${NC} $(stat -c '%w' "$homedir" 2>/dev/null || echo "н/д")"
		echo -e "${LC}Остання зміна:${NC} $(stat -c '%y' "$homedir")"
	else
		echo "Домашня директорія не існує"
	fi
	
	# --- Доступ ---
	echo -e "\n${CYAN}🔑  Доступ${NC}"
	echo -e "${LC}Пароль:${NC} $passwd_status_str"
	echo -e "${LC}Дата останньої зміни пароля:${NC} $passwd_last_change"
	echo -e "${LC}Мінімальна кількість днів між змінами пароля:${NC} $passwd_min"
	echo -e "${LC}Максимальна кількість днів дії пароля:${NC} $passwd_max"
	echo -e "${LC}Кількість днів попередження до закінчення дії пароля:${NC} $passwd_warn"
	echo -e "${LC}Кількість днів після закінчення терміну дії пароля, коли пароль буде заблокований:${NC} $passwd_inactive"
	echo -e "${LC}Shell:${NC} $shell_dsc"
	
	# --- Останній вхід ---
	local last_entry terminal ip login_date login_time login_year
	last_entry=$(last -n 1 -F "$user" | head -n 1)

	terminal=$(echo "$last_entry" | awk '{print $2}')
	ip=$(echo "$last_entry" | awk '{print $3}')
	login_date=$(echo "$last_entry" | awk '{print $4, $5, $6}')
	login_time=$(echo "$last_entry" | awk '{print $7}')
	login_year=$(echo "$last_entry" | awk '{print $8}')

	echo -e "\n${CYAN}📅  Останній вхід${NC}"
	echo -e "${LC}Термінал:${NC} $terminal"
	echo -e "${LC}IP:${NC} $ip"
	echo -e "${LC}Дата:${NC} $login_date $login_time $login_year"
	
	
	# --- Активні процеси ---
    echo -e "\n${CYAN}🖥️  Активні процеси${NC}"
    if ps -u "$user" --no-headers | grep -q .; then
        ps -u "$user" -o pid,tty,time,cmd
    else
        echo "Немає запущених процесів"
        return
    fi
	
	# --- Статистика активності ---
	local proc_count cpu_sum mem_sum mem_mb
	# Підрахунок сумарного CPU і Memory користувача
	proc_info=$(ps -u "$user" --no-headers -o %cpu,%mem | awk '{c+=$1; m+=$2; count++} END {printf "%d %.2f %.2f", count, c+0, m+0}')

	# Розбиваємо рядок на три змінні
	proc_count=$(echo "$proc_info" | awk '{print $1}')
	cpu_sum=$(echo "$proc_info" | awk '{print $2}')
	mem_sum=$(echo "$proc_info" | awk '{print $3}')

	# Отримуємо загальну пам’ять системи в MB
	total_mem=$(awk '/MemTotal/ {printf "%.1f", $2/1024}' /proc/meminfo)

	# Memory користувача в MB
	mem_mb=$(awk -v m="$mem_sum" -v t="$total_mem" 'BEGIN{printf "%.1f", m*t/100}')
	
	user_info__colorize() {
		local string="$1" value="$2" high="$3" medium="$4"
		if (( $(awk -v v="$value" -v h="$high" -v m="$medium" 'BEGIN{print (v>h)}') )); then
			echo -e "${RED}$string${NC}"
		elif (( $(awk -v v="$value" -v h="$high" -v m="$medium" 'BEGIN{print (v>m && v<=h)}') )); then
			echo -e "${YELLOW}$string${NC}"
		else
			echo -e "${GREEN}$string${NC}"
		fi
	}

	echo -e "\n${CYAN}📊  Статистика активності${NC}"
	echo -e "${LC}Кількість процесів:${NC} $proc_count"
	echo -en "${LC}Використання CPU:${NC} "
	user_info__colorize "$cpu_sum%" "$cpu_sum" 80 40

	echo -en "${LC}Використання пам’яті:${NC} "
	user_info__colorize "$mem_sum% ($mem_mb MB)" "$mem_sum" 60 30

    # --- Топ-5 процесів за CPU ---
    echo -e "\n${CYAN}🔝  Топ-5 процесів за CPU (частка від користувача)${NC}"
    ps -u "$user" -o pid,%cpu,%mem,time,cmd --sort=-%cpu | head -n 6 | awk -v total="$cpu_sum" -v red="$RED" -v yellow="$YELLOW" -v green="$GREEN" -v nc="$NC" '
        NR==1 {printf "%-8s %-6s %-6s %-10s %s\n", $1,$2,$3,$4,$5; next}
        {
            cpu=$2+0; mem=$3+0
            part=(total>0)?(cpu/total)*100:0
            color=green
            if(cpu>50) color=red
            else if(cpu>20) color=yellow
            printf "%-8s %s%-6.1f%s %-6.1f %-10s %s  (%.1f%%)\n", $1,color,cpu,nc,mem,$4,$5,part
        }'

    # --- Топ-5 процесів за пам’яттю ---
    echo -e "\n${CYAN}🔝  Топ-5 процесів за пам’яттю (частка від користувача)${NC}"
    ps -u "$user" -o pid,%cpu,%mem,time,cmd --sort=-%mem | head -n 6 | awk -v total="$mem_sum" -v red="$RED" -v yellow="$YELLOW" -v green="$GREEN" -v nc="$NC" '
        NR==1 {printf "%-8s %-6s %-6s %-10s %s\n", $1,$2,$3,$4,$5; next}
        {
            cpu=$2+0; mem=$3+0
            part=(total>0)?(mem/total)*100:0
            color=green
            if(mem>30) color=red
            else if(mem>15) color=yellow
            printf "%-8s %-6.1f %s%-6.1f%s %-10s %s  (%.1f%%)\n", $1,cpu,color,mem,nc,$4,$5,part
        }'
}

function users_info(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if ! is_array_single Users; then
	    echo -e "\n${CYAN_BOLD}$index Користувач $user:${NC}\n"
	  fi
	  user_info "$user"
	  echo
	  ((index++))
	done
}

function users_table_b(){
    local -n Users="$1"
    shift

    local -a Items=()

    # Default Items
    if (( $# == 0 )); then
        Items=(idx name uid gid group home shell)
    else
        local raw="$*"
		# замінюємо коми на пробіли
		raw="${raw//,/ }"
		# прибираємо повторні пробіли
		raw="${raw//+([[:space:]])/ }"   # потребує shopt -s extglob
		raw="${raw## }"  # видаляємо пробіл на початку
		raw="${raw%% }"  # видаляємо пробіл у кінці
		# розбиваємо у масив
		IFS=' ' read -r -a Items <<< "$raw"
    fi
	
	local rows
	local rows_count idx_digits sep_len
	
	# --- Заголовки ---
	local -A labels=(
		[idx]="#"
		[name]="Name"
		[uid]="UID"
		[gid]="GID"
		[group]="Group"
		[home]="Home DIR"
		[shell]="Shell"
	)
	
    # --- Макс ширини колонок ---
    local -A max_w
    for key in "${Items[@]}"; do
        max_w[$key]=${#labels[$key]}
    done

    # --- Збирання рядків ---
    local rows=()
    local idx=1
    for user in "${Users[@]}"; do
        if ! id "$user" &>/dev/null; then
            continue
        fi

        local user_info name uid gid home shell group row
        user_info=$(getent passwd "$user")
        IFS=: read -r name _ uid gid _ home shell <<< "$user_info"
        group=$(getent group "$gid" | cut -d: -f1)

        row=""
        for key in "${Items[@]}"; do
            [[ -n "$row" ]] && row+="|"
            local val
            val="${!key}"
            row+="$val"

            # оновлення макс ширини
            (( ${#val} > max_w[$key] )) && max_w[$key]=${#val}
        done

        rows+=("$row")
        ((idx++))
    done

    # --- Формування формату ---
    local fmt=""
    for key in "${Items[@]}"; do
        [[ -n "$fmt" ]] && fmt+=" ${GRAY}|${NC} "
        fmt+="%-${max_w[$key]}s"
    done
    fmt+="\n"
	
    # --- Шапка ---
    local -a header=()
    for key in "${Items[@]}"; do
        header+=("${labels[$key]:-$key}")
    done
    printf "$fmt" "${header[@]}"
	
    # --- Роздільник ---
    local sep_len=0
    for key in "${Items[@]}"; do
        ((sep_len += max_w[$key]))
    done
    ((sep_len += 3 * (${#Items[@]} - 1))) # для " | "
    printf "${GRAY}%*s${NC}\n" "$sep_len" '' | tr ' ' '-'

    # --- Дані ---
    for row in "${rows[@]}"; do
        IFS='|' read -ra cols <<< "$row"
        local line=""
        for i in "${!Items[@]}"; do
            [[ -n "$line" ]] && line+=" ${GRAY}|${NC} "
            printf -v cell_fmt "%-${max_w[${Items[i]}]}s" "${cols[i]}"
            line+="$cell_fmt"
        done
        printf "%b\n" "$line"
    done	
}

function users_table() {
    local -n Users="$1"
    shift

    local -a Items=()

    # --- Default Items ---
    if (( $# == 0 )); then
        Items=(idx name uid gid group home passwd shell)
    else
		local raw="$*"
		# замінюємо коми на пробіли
		raw="${raw//,/ }"
		# прибираємо повторні пробіли
		raw="${raw//+([[:space:]])/ }"   # потребує shopt -s extglob
		raw="${raw## }"  # видаляємо пробіл на початку
		raw="${raw%% }"  # видаляємо пробіл у кінці
		# розбиваємо у масив
		IFS=' ' read -r -a Items <<< "$raw"
    fi

    # --- Labels ---
    local -A labels=(
        [idx]="#"
        [name]="Name"
        [uid]="UID"
        [gid]="GID"
        [group]="Group"
		[groups]="Groups"
		[groups_ids]="Groups"
        [home]="Home DIR"
		[passwd]="Pwd"
        [shell]="Shell"
    )

    # --- Формуємо рядок шапки у правильному порядку ---
    local labels_str=""
    for key in "${Items[@]}"; do
        labels_str+="${labels[$key]:-$key}|"
    done
    labels_str=${labels_str%|}

    # --- Передаємо масив користувачів у awk ---
    awk -v items="${Items[*]}" -v gray="$GRAY" -v nc="$NC" -v labels_str="$labels_str" '
    BEGIN {
        split(items, item_arr)
        split(labels_str, label_arr, "|")
        
		for(i=1;i<=length(item_arr);i++) {
			key = item_arr[i]
			val = label_arr[i]
			label[key] = val
			if(length(val) > max_w[key]) max_w[key] = length(val)
		}
		
        idx = 1
    }
    {
        user = $0
        
		# --- Перевірка існування користувача ---
        cmd = "id -u \"" user "\""
        if (( cmd | getline u) <= 0 ) { close(cmd); next }
        close(cmd)

        # --- Отримуємо passwd ---
        cmd = "getent passwd \"" user "\""
        cmd | getline pw
        close(cmd)
        if(pw == "") next

        split(pw,f,":")
        name=f[1]; uid=f[3]; gid=f[4]; home=f[6]; shell=f[7]
		
		# --- Отримуємо passwd -S ---
		passwd_status="—"
		cmd = "passwd -S \"" user "\""
		cmd | getline pws
		close(cmd)
		if(pws > 0) {
			split(pws,a," ")
			passwd_status=a[2]
		}

        # --- Отримуємо групу ---
        cmd = "getent group " gid
        cmd | getline g
        close(cmd)
        split(g,gf,":")
        group = gf[1]
		
        # --- Додаткові групи ---
        cmd = "id -G \"" user "\""
        cmd | getline gids
        close(cmd)
		
        split(gids, g_arr, " ")
        groups_list = ""
		groups_ids_list = ""
        for(j=1;j<=length(g_arr);j++) {
            gid2 = g_arr[j]
            # Пропускаємо основну групу, якщо треба
            #if(gid2 == gid) continue
            cmd = "getent group " gid2
            cmd | getline gg
            close(cmd)
            split(gg, gf2, ":")
            gname2 = gf2[1]
            if(groups_list != "") groups_list = groups_list ", "
			if(groups_ids_list != "") groups_ids_list = groups_ids_list ", "
            groups_list = groups_list gname2
			groups_ids_list = groups_ids_list gid2 "(" gname2 ")"
        }
        if(groups_list == "") groups_list = "-"
		if(groups_ids_list == "") groups_ids_list = "-"

        # --- Зберігаємо дані ---
        for(i=1;i<=length(item_arr);i++) {
            key = item_arr[i]
            if(key=="idx") val=idx
            else if(key=="name") val=name
            else if(key=="uid") val=uid
            else if(key=="gid") val=gid
            else if(key=="group") val=group
            else if(key=="groups") val=groups_list
			else if(key=="groups_ids") val=groups_ids_list
            else if(key=="home") val=home
            else if(key=="passwd") val=passwd_status
			else if(key=="shell") val=shell
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
    }' <<< "${Users[*]}"
}

function groups_table() {
	local -n Groups="$1"
    shift

    local -a Items=()

    # --- Default Items ---
    if (( $# == 0 )); then
        Items=(idx name gid users)
    else
		local raw="$*"
		# замінюємо коми на пробіли
		raw="${raw//,/ }"
		# прибираємо повторні пробіли
		raw="${raw//+([[:space:]])/ }"   # потребує shopt -s extglob
		raw="${raw## }"  # видаляємо пробіл на початку
		raw="${raw%% }"  # видаляємо пробіл у кінці
		# розбиваємо у масив
		IFS=' ' read -r -a Items <<< "$raw"
    fi

    # --- Labels ---
    local -A labels=(
        [idx]="#"
        [name]="Name"
        [gid]="GID"
        [users]="Users"
		[users_ids]="Users"
    )

    # --- Формуємо рядок шапки у правильному порядку ---
    local labels_str=""
    for key in "${Items[@]}"; do
        labels_str+="${labels[$key]:-$key}|"
    done
    labels_str=${labels_str%|}
	
	awk -v items="${Items[*]}" -v gray="$GRAY" -v nc="$NC" -v labels_str="$labels_str" '
    BEGIN {
        split(items, item_arr)
        split(labels_str, label_arr, "|")
        
		for(i=1;i<=length(item_arr);i++) {
			key = item_arr[i]
			val = label_arr[i]
			label[key] = val
			if(length(val) > max_w[key]) max_w[key] = length(val)
		}
		
        idx = 1
    }
    {
        group = $0

        # --- Отримуємо інформацію про групу ---
        cmd = "getent group \"" group "\""
        cmd | getline gline
        close(cmd)

        if(gline == "") next
        split(gline, gf, ":")
        name = gf[1]
        gid = gf[3]
        users = gf[4]

        # --- Формуємо users або users_ids ---
        # secondary з getent group
        split(gf[4], uarr, ",")
        users_map_count = 0

        # додаємо secondary users у масив
        for(j in uarr) {
            if(uarr[j] != "") {
                users_map[uarr[j]] = 1
            }
        }

        # --- Додаємо primary users ---
        cmd3 = "getent passwd"
        while((cmd3 | getline pline) > 0) {
            split(pline, pf, ":")
            uname = pf[1]
            pgid = pf[4]
            if(pgid == gid) {
                users_map[uname] = 1
            }
        }
        close(cmd3)

        # --- Конвертуємо у відсортований список ---
        n = 0
        for(u in users_map) {
            if(u != "") {
                n++
                all_users[n] = u
            }
        }
        asort(all_users)

        if(n == 0) {
            users = "-"
            users_ids = "-"
        } else {
            users_str = ""
            users_ids_str = ""
            for(j=1;j<=n;j++) {
                uname = all_users[j]
                cmd2 = "id -u \"" uname "\""
                cmd2 | getline uid
                close(cmd2)
                if(j>1) {
                    users_str = users_str ", "
                    users_ids_str = users_ids_str ", "
                }
                users_str = users_str uname
                users_ids_str = users_ids_str uid "(" uname ")"
            }
            users = users_str
            users_ids = users_ids_str
        }

        # --- Зберігаємо дані ---
        for(i=1;i<=length(item_arr);i++) {
            key = item_arr[i]
            if(key=="idx") val=idx
            else if(key=="name") val=name
            else if(key=="gid") val=gid
            else if(key=="users") val=users
            else if(key=="users_ids") val=users_ids
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
    }' <<< "${Groups[*]}"
}

function get_users() {
    local -n filters="$1"
    local search="${2:-}"
	
	# Якщо третій аргумент переданий – використовуємо його як масив
    if [[ -n "${3+x}" ]]; then
        local -n required_filters="$3"
    else
        # Створюємо локальний пустий масив із цією назвою
        local -a required_filters=()
    fi
	
    # список sudo користувачів
    local sudo_users_str=""
	if in_array "admin" filters || in_array "admin" required_filters; then
		sudo_users_str=$(get-sudo-users | tr '\n' ',' | sed 's/,$//')
	fi
	
	# список веб-користувачів
    local web_users_str=""
	if in_array "webuser" filters || in_array "webuser" required_filters; then
		web_users_str=$(getent group webusers | awk -F: '{print $4}' | tr '\n' ',' | sed 's/,$//')
	fi
    
	local filters_str required_filters_str
	filters_str=$(IFS=','; echo "${filters[*]}")
	required_filters_str=$(IFS=','; echo "${required_filters[*]}")
	
    awk -F: \
        -v filters_list="$filters_str" \
		-v required_filters_list="$required_filters_str" \
		-v sudousers_list="$sudo_users_str" \
		-v webusers_list="$web_users_str" \
        -v s="$search" \
    '
    BEGIN {
		
		has_filters = (filters_list != "")
		has_required_filters = (required_filters_list != "")
		
		# filters
		split(filters_list, arr, ",")
		for (i in arr) {
			if (arr[i] != "") filters[arr[i]]=1
		}
		split(required_filters_list, arr, ",")
		for (i in arr) {
			if (arr[i] != "") required_filters[arr[i]]=1
		}

        # sudo users
        if ("admin" in filters || "admin" in required_filters) {
			n = split(sudousers_list, arr, ",")
			for (i=1; i<=n; i++) {
				gsub(/^ +| +$/, "", arr[i])
				sudo_users[arr[i]]=1
			}
        }
		
		# web users
		if ("webuser" in filters || "webuser" in required_filters) {
			split(webusers_list, arr, ",")
			for (i in arr) {
				if (arr[i] != "") web_users[arr[i]]=1
			}		
		}
        
		# required users
        if ("required" in filters) {
            required_users["root"]=1
            required_users["nobody"]=1
            required_users["daemon"]=1
            required_users["bin"]=1
            required_users["www-data"]=1
			required_users["vmail"]=1
        }

        # інтерактивні shell для SSH
        interactive_shells["/bin/bash"]=1
        interactive_shells["/bin/sh"]=1
        interactive_shells["/bin/zsh"]=1
        interactive_shells["/bin/ksh"]=1
        interactive_shells["/bin/dash"]=1
		
    }
    {
        name=$1
        uid=$3
        home=$6
        sh=$7
        pass=0
		
		allow=1
		
		if (has_required_filters) {
			
			for (f in required_filters) {
				if (f == "webuser" && !(name in web_users)){ allow=0; break }
				if (f == "admin" && !(name in sudo_users)){ allow=0; break }
				if (f == "local" && uid<1000){ allow=0; break }
				if (f == "sys" && uid>=1000){ allow=0; break }
			}

		}
		
		if (!allow) next
		
		passwd_status=""
		if ("no_passwd" in filters || "locked" in filters) {
			cmd="passwd -S " name " 2>/dev/null"
            if ((cmd | getline line) > 0) {
                split(line,a," ")
				passwd_status=a[2]
             }
            close(cmd)
		}

        # root
        if ("root" in filters && uid==0) pass=1

        # service (системні користувачі до 1000)
        if ("service" in filters && uid<1000 && uid>0 && name!="root") pass=1

		# admin
        if ("admin" in filters && name in sudo_users) pass=1

        # webuser
        if ("webuser" in filters && name in web_users) pass=1

        # required
        if ("required" in filters && (name in required_users || name ~ /^systemd-/)) pass=1

        # shell
        if ("shell" in filters && (sh in interactive_shells)) pass=1

        # no_shell
        if ("no_shell" in filters && !(sh in interactive_shells)) pass=1

        # no_passwd
        if ("no_passwd" in filters && passwd_status=="NP") pass=1

        # locked
		if ("locked" in filters && (passwd_status=="L" || passwd_status=="LK") && !(sh in interactive_shells)) pass=1
 
        # якщо нічого не вибрано — всі користувачі
        if (!has_filters) pass=1

        # застосовуємо пошук
        if (pass && s != "" && name !~ s) pass=0

        if (pass) print name
    }' /etc/passwd | sort -u
}

function get_groups() {
	local -n filters="$1"
    local search="${2:-}"

    local filter_webuser=false
	local filter_webusers=false
    local filter_admin=false
	local filter_admins=false
    local filter_service=false
    local filter_root=false
    local filter_required=false
	local filter_notempty=false
	local filter_empty=false

    for f in "${filters[@]}"; do
        case "$f" in
            webuser)   filter_webuser=true ;;
			webusers)  filter_webusers=true ;;
            admin)     filter_admin=true ;;
			admins)     filter_admins=true ;;
            service)   filter_service=true ;;
            root)      filter_root=true ;;
            required)  filter_required=true ;;
			notempty)  filter_notempty=true ;;
			empty)     filter_empty=true ;;
        esac
    done
	
	# список веб-користувачів
    local web_users=""
	if [[ "$filter_webuser" == "true" ]]; then
		web_users=$(getent group webusers | awk -F: '{print $4}' | tr '\n' ',' | sed 's/,$//')
	fi
	
	# список sudo користувачів
    local sudo_users=""
	if [[ "$filter_admin" == "true" ]]; then
		sudo_users=$(get-sudo-users | tr '\n' ',' | sed 's/,$//')
	fi
	
	# список sudo груп
    local sudo_groups=""
	if [[ "$filter_admins" == "true" ]]; then
		sudo_groups=$(get-sudo-groups | tr '\n' ',' | sed 's/,$//')
	fi

    getent group | awk -F: \
        -v webuser="$filter_webuser" \
		-v webusers="$filter_webusers" \
        -v admin="$filter_admin" \
		-v admins="$filter_admins" \
        -v service="$filter_service" \
        -v root="$filter_root" \
        -v required="$filter_required" \
		-v notempty="$filter_notempty" \
		-v empty="$filter_empty" \
        -v s="$search" \
		-v webusers_list="$web_users" \
		-v sudousers_list="$sudo_users" \
		-v sudogroups_list="$sudo_groups" \
    '
    BEGIN {
	
		# sudo users
        if (admin=="true") {
			n = split(sudousers_list, arr, ",")
			for (i=1; i<=n; i++) {
				gsub(/^ +| +$/, "", arr[i])
				sudo_users[arr[i]]=1
			}
        }
		
		# sudo groups
        if (admins=="true") {
			n = split(sudogroups_list, arr, ",")
			for (i=1; i<=n; i++) {
				gsub(/^ +| +$/, "", arr[i])
				sudo_groups[arr[i]]=1
			}
        }
		
		# web users
		if (webuser=="true") {
			split(webusers_list, arr, ",")
			for (i in arr) {
				if (arr[i] != "") web_users[arr[i]]=1
			}		
		}
		
        # required groups
        if (required=="true") {
            required_groups["root"]=1
            required_groups["sudo"]=1
            required_groups["adm"]=1
            required_groups["www-data"]=1
            required_groups["mail"]=1
            required_groups["vmail"]=1
        }

    }
    {
        name=$1
        gid=$3
        users_field=$4
        gsub(/^,|,$/, "", users_field)
        split(users_field, user_list, ",")

        user_count = 0
        for (u in user_list) {
            if (user_list[u] != "") user_count++
        }
		
        pass=0

        # root
        if (root=="true" && gid==0) pass=1

        # service
        if (service=="true" && gid<1000 && gid>0) pass=1
		
		# admin — групи з іменами, що збігаються з sudo users
        if (admin=="true" && name in sudo_users) pass=1

        # admins
		if (admins=="true" && name in sudo_groups) pass=1

        # webuser — групи з іменами, що збігаються з web users
        if (webuser=="true" && (name in web_users)) pass=1
		
		# webusers
        if (webusers=="true" && name="webusers") pass=1

        # required
        if (required=="true" && (name in required_groups)) pass=1
		
        # notempty
        if (notempty=="true" && user_count>0) pass=1
        if (notempty=="true" && user_count==0) pass=0

        # empty
        if (empty=="true" && user_count==0) pass=1
        if (empty=="true" && user_count>0) pass=0

        # якщо нічого не вибрано → всі
        if (admin=="false" && admins=="false" && webuser=="false" && webusers=="false" && service=="false" && root=="false" && required=="false" && notempty=="false" && empty=="false") {
            pass=1
        }

        # пошук
        if (pass && s != "" && name !~ s) pass=0

        if (pass) print name
    }' | sort -u
}

function lock_users(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    lock-user "$user"
	  else
	    if user_isset "$user"; then
		  if lock-user "$user" &>/dev/null; then
			value="$(get_log_success "Користувача $user заблоковано")"
		  else
		    value="$(get_log_error "Не вдалося заблокувати користувача $user")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done
}

function lock_users_passwd(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    lock-user "$user" -p
	  else
	    if user_isset "$user"; then
		  if lock-user "$user" -p &>/dev/null; then
			value="$(get_log_success "Користувача $user заблоковано")"
		  else
		    value="$(get_log_error "Не вдалося заблокувати користувача $user")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done
}

function lock_users_shells(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    lock-user "$user" -s
	  else
	    if user_isset "$user"; then
		  if lock-user "$user" -s &>/dev/null; then
			value="$(get_log_success "Користувача $user заблоковано")"
		  else
		    value="$(get_log_error "Не вдалося заблокувати користувача $user")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done
}

function unlock_users(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    unlock-user "$user"
	  else
	    if user_isset "$user"; then
		  if unlock-user "$user" &>/dev/null; then
			value="$(get_log_success "Користувача $user розблоковано")"
		  else
		    value="$(get_log_error "Не вдалося розблокувати користувача $user")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done
}

function unlock_users_passwd(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    unlock-user "$user" -p
	  else
	    if user_isset "$user"; then
		  if unlock-user "$user" -p &>/dev/null; then
			value="$(get_log_success "Користувача $user розблоковано")"
		  else
		    value="$(get_log_error "Не вдалося розблокувати користувача $user")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done
}

function unlock_users_shells(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    unlock-user "$user" -s
	  else
	    if user_isset "$user"; then
		  if unlock-user "$user" -s &>/dev/null; then
			value="$(get_log_success "Користувача $user розблоковано")"
		  else
		    value="$(get_log_error "Не вдалося розблокувати користувача $user")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done
}

function delete_users(){
	local -n Users="$1"
	
	local index=1
    for user in "${Users[@]}"; do
	  delete-user "$user"
	  echo
	  ((index++))
	done
}

function change_users_passwd(){
	local -n Users="$1"
	
	local index=1
    for user in "${users[@]}"; do
	  if user_isset "$user"; then
	    if passwd "$user"; then
		  log_success "Пароль для користувача $user змінено"
		else
		  log_error "Не вдалося змінити пароль користувача $user"
		fi
	  else
		log_error "Користувача $user не знайдено"
	  fi
	  ((index++))
	done
}

function change_users_dirs(){
	local -n Users="$1"
	
	local index=1
	for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    change-user-dir "$user"
	  else
	    if user_isset "$user"; then
		  if change-user-dir "$user"; then
		    homedir="$(getent passwd "$user" | cut -d: -f6)"
			value="$(get_log_success "$homedir")"
		  else
		    value="$(get_log_error "Не вдалося змінити домашню директорію")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done	
}

function change_users_shells(){
	local -n Users="$1"
	
	local newshell
	local SELECTED_SHELLS=()
	
	local AVAILABLE_SHELLS
	readarray -t AVAILABLE_SHELLS < <(grep -vE '^\s*#' /etc/shells)
	
	# Enter shell
	echo "Введіть назву Shell або натисніть Enter щоб вибрати."
	read -p "Назва Shell: " newshell
	
	if [[ -n "$newshell" ]]; then
		if ! in_array "$newshell" AVAILABLE_SHELLS; then
			newshell=""
			log_warn "Невірний Shell"
		fi
	fi
	
	if [[ -z "$newshell" ]]; then
	
	# Select shell
		
	[[ -z "$AVAILABLE_SHELLS" ]] && {
		log_error "Доступних Shells не знайдено"
		return 2
	}
	
	echo -e "${BOLD}Виберіть Shell:${NC}\n"
			  
	components_list AVAILABLE_SHELLS
	
	echo
	menu_divider
	echo -e "${BOLD}✔️  Обрати${NC}"
	menu_nav
	
	while true; do
		
		echo   
		read -rp "> " input
		
		case "$input" in
			"") log_error "Нічого не вибрано"; continue ;;
			c) return 1 ;;
			x) exit 0 ;;
			*)
			  choose_items "$input" AVAILABLE_SHELLS SELECTED_SHELLS
			  if ! is_array_empty SELECTED_SHELLS; then
				newshell="${SELECTED_SHELLS[0]}"
				break
			  else
				continue
			  fi
			  ;;
		esac
	done
		
	fi
	
	if [[ -z "$newshell" ]]; then
		log_error "Shell не вибрано"
		return 1
	fi
	
	echo
	
	local index=1
	for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    change-user-shell "$user" "$newshell"
	  else
	    if user_isset "$user"; then
		  if change-user-shell "$user" "$newshell" &>/dev/null; then
		    shell="$(getent passwd "$user" | cut -d: -f7)"
			value="$(get_log_success "$shell")"
		  else
		    value="$(get_log_error "Не вдалося змінити Shell-доступ")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done
}

function add_users_to_group(){
	local -n Users="$1"
	
	local SELECTED_GROUPS=()
	
	# Enter group
	echo "Введіть назву групи або натисніть Enter щоб вибрати."
	read -p "Назва групи: " newgroup
	
	if [[ -n "$newgroup" ]] && ! group_isset "$newgroup"; then
		log_warn "Групу $newgroup не знайдено"
		newgroup=""
	fi
	
	if [[ -n "$newgroup" ]]; then
		SELECTED_GROUPS=("$newgroup")
	else
	
	# Select group
	
	local group_filter=()
	local groups=()
	get_group_components group_filter groups
			  
	[[ -z "$groups" ]] && {
		log_error "Груп не знайдено"
		return 2
	}
	
	echo -e "${BOLD}Виберіть групу:${NC}\n"
			  
	components_list groups
	
	echo
	menu_divider
	echo -e "${BOLD}✔️  Обрати${NC}"
	menu_nav
	
	while true; do
		
		echo   
		read -rp "> " input
		
		case "$input" in
			"") log_error "Нічого не вибрано"; continue ;;
			c) return 1 ;;
			x) exit 0 ;;
			*)
			  choose_items "$input" groups SELECTED_GROUPS
			  if ! is_array_empty SELECTED_GROUPS; then
				break
			  else
				continue
			  fi
			  ;;
		esac
	done
	
	fi
	
	[[ -z "$SELECTED_GROUPS" ]] && {
		log_error "Групу не вибрано"
		return 2
	}
	
	for group in "${SELECTED_GROUPS[@]}"; do
	
	echo
	if ! is_array_single SELECTED_GROUPS; then
		echo -e "${BOLD}Група $group:${NC}\n"
	fi

	local index=1
    for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    add-user-to-group "$user" "$group"
	  else
	    if user_isset "$user"; then
		  if add-user-to-group "$user" "$group" &>/dev/null; then
			groups=$(id -nG "$user" | sed 's/ /, /g')
			value="$(get_log_success "Групи користувача: $groups")"
		  else
		    value="$(get_log_error "Не вдалося додати до групи")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done

	done
}

function delete_users_from_group(){
	local -n Users="$1"
	
	local SELECTED_GROUPS=()
	
	# Enter group
	echo "Введіть назву групи або натисніть Enter щоб вибрати."
	read -p "Назва групи: " newgroup
	
	if [[ -n "$newgroup" ]] && ! group_isset "$newgroup"; then
		log_warn "Групу $newgroup не знайдено"
		newgroup=""
	fi
	
	if [[ -n "$newgroup" ]]; then
		SELECTED_GROUPS=("$newgroup")
	else
	
	# Select group
	
	local group_filter=()
	local groups=()
	get_group_components group_filter groups
			  
	[[ -z "$groups" ]] && {
		log_error "Груп не знайдено"
		return 2
	}
	
	echo -e "${BOLD}Виберіть групу:${NC}\n"
			  
	components_list groups
	
	echo
	menu_divider
	echo -e "${BOLD}✔️  Обрати${NC}"
	menu_nav
	
	while true; do
		
		echo   
		read -rp "> " input
		
		case "$input" in
			"") log_error "Нічого не вибрано"; continue ;;
			c) return 1 ;;
			x) exit 0 ;;
			*)
			  choose_items "$input" groups SELECTED_GROUPS
			  if ! is_array_empty SELECTED_GROUPS; then
				break
			  else
				continue
			  fi
			  ;;
		esac
	done
	
	fi
	
	[[ -z "$SELECTED_GROUPS" ]] && {
		log_error "Груп не знайдено"
		return 2
	}
	
	for group in "${SELECTED_GROUPS[@]}"; do
	
	echo
	if ! is_array_single SELECTED_GROUPS; then
		echo -e "${BOLD}Група $group:${NC}\n"
	fi

	local index=1
	for user in "${Users[@]}"; do
	  if is_array_single Users; then
	    delete-user-from-group "$user" "$group"
	  else
	    if user_isset "$user"; then
		  if delete-user-from-group "$user" "$group" &>/dev/null; then
			groups=$(id -nG "$user" | sed 's/ /, /g')
			value="$(get_log_success "Групи користувача: $groups")"
		  else
		    value="$(get_log_error "Не вдалося видалити з групи")"
		  fi
		else
		  value="$(get_log_error "Користувача не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$user" "$value"
	  fi
	  ((index++))
	done

	done
}

# Додавання групи
function add_group() {
    read -p "Назва нової групи: " newgroup
    sudo groupadd "$newgroup"
}

function delete_groups(){
	local -n Groups="$1"
	
	local index=1
    for group in "${Groups[@]}"; do
	  if is_array_single Groups; then
	    delete-group "$group"
	  else
	    if user_isset "$group"; then
		  if delete-group "$group" -y &>/dev/null; then
			value="$(get_log_success "Групу $group видалено")"
		  else
		    value="$(get_log_error "Не вдалося видалити групу $group")"
		  fi
		else
		  value="$(get_log_error "Групи не знайдено")"
		fi
		printf "%-4s %-30s %s\n" "$index" "$group" "$value"
	  fi
	  ((index++))
	done
}

function get_user_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local ITEMS=()
  
  readarray -t ITEMS < <(get_users Filters "$SEARCH")
  
  _out=("${ITEMS[@]}")
}

function get_localuser_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local ITEMS=()
  
  local _Filters=("local")
  
  readarray -t ITEMS < <(get_users Filters "$SEARCH" _Filters)
  
  _out=("${ITEMS[@]}")
}

function get_sysuser_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local ITEMS=()
  
  local _Filters=("sys")
  
  readarray -t ITEMS < <(get_users Filters "$SEARCH" _Filters)
  
  _out=("${ITEMS[@]}")
}

function get_group_components() {
  local -n Filters="$1"
  local -n _out=$2
  _out=()
  
  local ITEMS=()
  
  readarray -t ITEMS < <(get_groups Filters "$SEARCH")
  
  _out=("${ITEMS[@]}")
}

function action_user_components() {
  local -n actions="$1"
  local -n users="$2"
  local label user value
  
  local -A action_names=(
    [add]="Створення користувача"
	[data]="Дані користувачів"
	[data_single]="Дані користувача {user}"
	[info]="Інформація про користувача"
	[info_single]="Інформація про користувача {user}"
	[home]="Домашня директорія користувачів"
	[home_single]="Домашня директорія користувача {user}"
	[shell]="Shell-доступ користувачів"
	[shell_single]="Shell-доступ користувача {user}"
	[id]="UID і GID користувачів"
	[id_single]="UID і GID користувача {user}"
	[passwd]="Зміна паролю користувачів"
	[passwd_single]="Зміна паролю користувача {user}"
	[change_shell]="Зміна Shell-доступ користувачів"
	[change_shell_single]="Зміна Shell-доступ користувача {user}"
	[change_home]="Зміна домашньої директорії користувачів"
	[change_home_single]="Зміна домашньої директорії користувача {user}"
	[groups]="Групи користувачів"
	[groups_single]="Групи користувача {user}"
	[delete]="Видалення користувачів"
	[delete_single]="Видалення користувача {user}"
	[lock]="Блокування користувачів"
	[lock_single]="Блокування користувача {user}"
	[unlock]="Розблокування користувачів"
	[unlock_single]="Розблокування користувача {user}"
	[add_to_group]="Додавання користувачів до групи"
	[add_to_group_single]="Додавання користувача {user} до групи"
	[delete_from_group]="Видалення користувачів з групи"
	[delete_from_group_single]="Видалення користувача {user} з групи"
	[ftpusers]="FTP-користувчі локальних користувачів"
	[ftpusers_single]="FTP-користувчі локального користувача {user}"
  )
  
  action_user_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    # заміна {user} на значення змінної $user
	text="${text//\{user\}/${user:-}}"
    echo "$text"
  }
  
  is_array_empty users && log_warn "Користувачі не вказані" && return 2
  is_array_empty actions && log_warn "Дії не вказані" && return 2
  
  for action in "${actions[@]}"; do
	
	user="${users[0]:-}"
	if is_array_single users && array_key_has_value "${action}_single" action_names; then
		label=$(action_user_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_user_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
	  add) add-user ;;
	  info) users_info users ;;
	  data) users_table users ;;
	  passwd) change_users_passwd users ;;
	  home) is_array_single users && user_homedir "${users[0]}" || users_table users "idx name home" ;;
	  change_home) change_users_dirs users ;;
	  id) users_table users "idx name uid gid groups_ids" ;;
	  lock) lock_users users ;;
	  lock_passwd) lock_users_passwd users ;;
	  lock_shell) lock_users_shells users ;;
	  unlock) unlock_users users ;;
	  unlock_passwd) unlock_users_passwd users ;;
	  unlock_shell) unlock_users_shells users ;;
	  delete) delete_users users ;;
	  shell) is_array_single users && user_shell "${users[0]}" || users_table users "idx name shell" ;;
	  change_shell) change_users_shells users  ;;
	  groups) is_array_single users && user_groups "${users[0]}" || users_table users "idx name groups" ;;
	  add_to_group) add_users_to_group users ;;
	  delete_from_group) delete_users_from_group users ;;
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

function action_localuser_components() {
	local -n _ACTIONS="$1"
	local -n _COMPONENTS="$2"
  
	action_user_components _ACTIONS _COMPONENTS
}

function action_sysuser_components() {
	local -n _ACTIONS="$1"
	local -n _COMPONENTS="$2"
  
	action_user_components _ACTIONS _COMPONENTS
}

function action_group_components() {
  local -n actions="$1"
  local -n groups="$2"
  local label group value
  
  local -A action_names=(
	[add]="Створення групи"
	[id]="GID і UID користувачів"
	[users]="Користувачі груп"
	[users_single]="Користувачі групи {group}"
	[delete]="Видалення груп"
	[delete_single]="Видалення групи {group}"
  )
  
  action_group_components__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    # заміна {group} на значення змінної $group
	text="${text//\{group\}/${group:-}}"
    echo "$text"
  }
  
  is_array_empty groups && log_warn "Групи не вказані" && return 2
  is_array_empty actions && log_warn "Дії не вказані" && return 2
  
  for action in "${actions[@]}"; do
	
	group="${groups[0]:-}"
	if is_array_single groups && array_key_has_value "${action}_single" action_names; then
		label=$(action_group_components__get_label "${action}_single")
	elif array_key_has_value "$action" action_names; then
        label=$(action_group_components__get_label "$action")
    else
        label="$action"
    fi

    echo -e "${YELLOW_BOLD}$label${NC}\n"
	
	case "$action" in
	  add) add_group ;;
	  delete) delete_groups groups ;;
	  id) groups_table groups "idx name gid users_ids" ;;
	  users) groups_table groups "idx name users" ;;
      *) log_error "Невідома дія: $action" ;;
	esac
  
  done
}

function show_groups_list(){
	getent group
}

function user_component_action() {
  local -n actions="$1"
  local label

  is_array_empty actions && log_warn "Нічого не вибрано" && return 2
  
  local -A action_names=(
    [add_user]="Створення користувача"
	[add_group]="Створення групи"
	[os_login]="Перевірка OS Login"
	[shells]="Доступні Shells для входу"
  )
  
  user_component_action__get_label() {
    local key="$1"
    local text="${action_names[$key]:-$key}"
    echo "$text"
  }
  
  for action in "${actions[@]}"; do
	
	if array_key_has_value "$action" action_names; then
        label=$(user_component_action__get_label "$action")
		echo -e "\n${YELLOW_BOLD}$label${NC}"
    fi
	
	case "$action" in
		add_user) add-user ;;
		add_webuser) add-webuser ;;
		add_ftpuser) add-ftpuser ;;
        localusers)
			local TYPE="localuser"
			component_menu
			;;
		sysusers)
			local TYPE="sysuser"
			component_menu
			;;
		webusers)
			local TYPE="webuser"
			get_component_file TYPE comp_file
			if [[ -f $comp_file ]]; then
				source "$comp_file"
			else
				log_error "Модуль для $TYPE не знайдено: $comp_file"
				return 2
			fi

			component_menu
			;;
		ftpusers)
			local TYPE="ftpuser"
			get_component_file TYPE comp_file
			if [[ -f $comp_file ]]; then
				source "$comp_file"
			else
				log_error "Модуль для $TYPE не знайдено: $comp_file"
				return 2
			fi
			component_menu
			;;
		add_group) add_group ;;
		groups) 
			local TYPE="group"; 
			component_menu
			;;
		os_login) check-oslogin ;;
		shells) available_shells_list ;;
	esac
  
  done
}

function show_user_filter_menu() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}"
    echo "Усі"
    echo "1) Веб-користувачі"
	echo "2) Адміністратори"
	echo "3) Сервісні"
	echo "4) Root"
	echo "5) Обов'язкові"
	echo "6) Із SSH-доступом"
	echo "7) Без SSH-доступу"
	echo "8) Без паролю"
	echo "9) Заблоковані"
	echo "s) Шукати за назвою"
	menu_nav
}

function parse_user_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
            1) FILTER+=("webuser") ;;
            2) FILTER+=("admin") ;;
            3) FILTER+=("service") ;;
			4) FILTER+=("root") ;;
			5) FILTER+=("required") ;;
			6) FILTER+=("shell") ;;
			7) FILTER+=("no_shell") ;;
			8) FILTER+=("no_passwd") ;;
			9) FILTER+=("locked") ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_user_action_menu() {
	menu_header "🛠️  Керування користувачами"
    echo "1) Додати нового користувача"
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
	menu_header "📊  Інформація та діагностика"
	echo "21) Показати дані користувачів"
    echo "22) Показати інформацію про користувача"
    echo "23) Перевірити домашню директорію"
	echo "24) Перевірити Shell-доступ"
	echo "25) Перевірити ID"
	echo "26) Перевірити групи"
	echo "27) Перевірити FTP-користувачів"
	menu_nav
}

function parse_user_action_choices() {
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

function show_localuser_filter_menu() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}"
    echo "Усі"
    echo "1) Веб-користувачі"
	echo "2) Адміністратори"
	echo "3) Обов'язкові"
	echo "4) Із SSH-доступом"
	echo "5) Без SSH-доступу"
	echo "6) Без паролю"
	echo "7) Заблоковані"
	echo "s) Шукати за назвою"
	menu_nav
}
function parse_localuser_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
            1) FILTER+=("webuser") ;;
            2) FILTER+=("admin") ;;
			3) FILTER+=("required") ;;
			4) FILTER+=("shell") ;;
			5) FILTER+=("no_shell") ;;
			6) FILTER+=("no_passwd") ;;
			7) FILTER+=("locked") ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}
function show_localuser_action_menu() {
	show_user_action_menu
}
function parse_localuser_action_choices() {
	parse_user_action_choices
}

function show_sysuser_filter_menu() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}"
    echo "Усі"
	echo "1) Адміністратори"
	echo "2) Сервісні"
	echo "3) Root"
	echo "4) Обов'язкові"
	echo "5) Із SSH-доступом"
	echo "6) Без SSH-доступу"
	echo "7) Без паролю"
	echo "8) Заблоковані"
	echo "s) Шукати за назвою"
	menu_nav
}
function parse_sysuser_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
            1) FILTER+=("admin") ;;
            2) FILTER+=("service") ;;
			3) FILTER+=("root") ;;
			4) FILTER+=("required") ;;
			5) FILTER+=("shell") ;;
			6) FILTER+=("no_shell") ;;
			7) FILTER+=("no_passwd") ;;
			8) FILTER+=("locked") ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}
function show_sysuser_action_menu() {
	show_user_action_menu
}
function parse_sysuser_action_choices() {
	parse_user_action_choices
}

function show_group_filter_menu() {
	menu_header "${HEADER_LABELS[$TYPE]:-$TYPE}"
    echo "Усі"
	echo "1) Веб-користувачів"
	echo "2) Адміністраторів"
	echo "3) Сервісні"
	echo "4) Root"
	echo "5) Обов'язкові"
	echo "6) З веб-користувачами"
	echo "7) З адміністраторами"
	echo "8) З користувачами"
	echo "9) Без користувачів"
	echo "s) Шукати за назвою"
	menu_nav
}

function parse_group_filter_choices() {
    local choice
    for choice in "${choices[@]}"; do
        case "$choice" in
            "") FILTER+=("all") ;;
            1) FILTER+=("webuser") ;;
			2) FILTER+=("admin") ;;
			3) FILTER+=("service") ;;
			4) FILTER+=("root") ;;
			5) FILTER+=("required") ;;
			6) FILTER+=("webusers") ;;
            7) FILTER+=("admins") ;;
			8) FILTER+=("notempty") ;;
			9) FILTER+=("empty") ;;
			s) FILTER+=("search") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function show_group_action_menu() {
	menu_header "🛠️  Керування групами користувачів"
    echo "1) Додати нову групу"
    echo "2) Видалити"
	menu_header "📊  Інформація та діагностика"
	echo "11) Перевірити ID"
	echo "12) Перевірити користувачів групи"
	menu_nav
}

function parse_group_action_choices() {
    local choice
	
	if [[ ${#choices[@]} -eq 0 ]]; then
		log_error "Нічого не вибрано"
		return 2
	fi
	
    for choice in "${choices[@]}"; do
        case "$choice" in
            1) ACTION+=("add") ;;
			2) ACTION+=("delete") ;;
			11) ACTION+=("id") ;;
			12) ACTION+=("users") ;;
            c) return 1 ;;
            x) exit 0 ;;
            *) log_error "Некоректний вибір"; return 2 ;;
        esac
    done
}

function user_component_menu() {
	component_type_menu
}

function user_select_menu_items() {
	
	local -n Items="$1"
	local -n Labels="$2"
	
	local menu_items=()
	local menu_parts=()
	local user_menu_items group_menu_items settings_menu_items
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[user_menu]="Користувачі"
		[group_menu]="Групи"
		[settings_menu]="Налаштування"
		[user_menu_header]="${HEADER_LABELS[$TYPE]:-$TYPE}"
		[group_menu_header]="${HEADER_LABELS[group]:-}"
		[settings_menu_header]="${HEADER_LABELS[settings]:-}"
		[add_user]="Додати нового користувача"
		[add_webuser]="Додати нового веб-користувача"
		[add_ftpuser]="Додати нового FTP-користувача"
        [localusers]="Локальні користувачі"
		[sysusers]="Системні користувачі"
		[webusers]="Веб-користувачі"
		[ftpusers]="FTP-користувачі"
		[add_group]="Додати нову групу"
		[groups]="Групи користувачів"
		[os_login]="Перевірити OS Login"
		[shells]="Перевірити доступні Shells для входу"
	)
	
	menu_parts=(
		user_menu
		group_menu
		settings_menu
	)
	
	user_menu_items=(
		add_user
		add_webuser
		add_ftpuser
        localusers
		sysusers
		webusers
		ftpusers
	)
	
	group_menu_items=(
		add_group
		groups
	)
	
	settings_menu_items=(
		os_login
		shells
	)

	# menu choose
	if [[ "$MENU_CHOOSE_TYPE" == "menu_choose" ]]; then
	
		menu_items=("${user_menu_items[@]}")
		
		for key in "${menu_parts[@]}"; do
			[[ "$key" == "user_menu" ]] && continue
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

function localuser_filter_menu_items(){

	local -n Items="$1"
	local -n Labels="$2"

	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[all]="Усі"
		[webuser]="Веб-користувачі"
		[admin]="Адміністратори"
		[required]="Обов'язкові"
		[shell]="Із SSH-доступом"
		[no_shell]="Без SSH-доступу"
		[no_passwd]="Без паролю"
		[locked]="Заблоковані"
		[search]="Шукати за назвою"
	)

	Items=(
		all
		webuser
		admin
		required
		shell
		no_shell
		no_passwd
		locked
		search
	)
}

function sysuser_filter_menu_items(){
	
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
		admin
		service
		root
		required
		shell
		no_shell
		no_passwd
		locked
		search
	)
}

function user_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[add]="Додати нового користувача"
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
		[data]="Показати дані користувачів"
		[info]="Показати інформацію про користувача"
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

function localuser_action_menu_items() {
    user_action_menu_items "$@"
}
function sysuser_action_menu_items() {
    user_action_menu_items "$@"
}

function group_action_menu_items(){
	
	local -n Items="$1"
	local -n Labels="$2"
	
	Labels=(
		[c]="Скасувати"
		[x]="Вийти"
		[cancel]="${HEADER_LABELS[cancel]:-}"
		[exit]="${HEADER_LABELS[exit]:-}"
		[add]="Додати нову групу"
		[delete]="Видалити"
		[id]="Перевірити ID"
		[users]="Перевірити користувачів групи"
	)
	
	Items=(
		add
		delete
		id
		users
	)
}
