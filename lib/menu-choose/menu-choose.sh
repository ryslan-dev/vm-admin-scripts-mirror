# Функціонал menu-choose.sh
# ─────────────────────────────────────────────────────────────────────────────
# Особливості:
# - Часткова промальовка (без миготіння)
# - Прихований системний курсор на час меню
# - Очищення ТІЛЬКИ своєї області (без стирання історії/шапки)
# - Опційний альтернативний екран (як у vim/less) — ідеально чистий scrollback
# - Акуратний вихід по Ctrl+C/Ctrl+Q без «абракадабри» ^[[A...
# - Підтримка багаторядкового header
# - multi-вибір через пробіл
#
# Керування альтернативним екраном:
# - Іменний аргумент у функції: altscreen=1|0|on|off|alt|main|auto (має пріоритет)
# - Або змінна оточення: MENU_CHOOSE_ALTSCREEN=1|0
#
# Повернення:
#   0   = OK  (ok/apply/save/done/confirm) 				  (actionvar="ok"   або лейбл дії)
#   RC_CANCEL (def 2) = CANCEL (Esc/Cancel/Clear/None/No) (actionvar="esc"  або лейбл дії)
#   RC_EXIT   (def 3) = EXIT (Exit/Quit/Ctrl+Q)           (actionvar="exit" або лейбл дії)
#   130       = ABORT (Ctrl+C)                            (actionvar="abort")
#
# actionvar: якщо натиснули кнопку на панелі — повертає точний лейбл дії (як у actions),
#            інакше — одне з: ok / esc / exit / abort (за fallback-правилами).
# ─────────────────────────────────────────────────────────────────────────────
  
  # Хелпер для альтернативного екрану
  enter_alt() {
    (( use_alt != 1 )) && return 1
	# Спробувати через terminfo
    if tput smcup 2>/dev/null; then
      alt_used=1
    else
	  # Фолбек: DECSET 1049 (найсумісніше на сучасних емуляторах)
      printf '\e[?1049h' || return 1
      alt_used=1
    fi
	# Почати малювання з чистого екрана та з (1,1)
    tput clear 2>/dev/null || printf '\e[2J'
    tput home  2>/dev/null || printf '\e[H'
    return 0
  }
  leave_alt() {
    (( alt_used == 0 )) && return 0
    if tput rmcup 2>/dev/null; then :; else printf '\e[?1049l'; fi
    alt_used=0
  }

  # Хелпер: злити хвіст вводу з /dev/tty, щоб після Ctrl+C нічого не «дописувалось» у шелл
  drain_tty_input() {
	# тимчасово увімкнути «неканонічний миттєвий» режим, щоб читати без блокувань
    stty -icanon -echo min 0 time 0 </dev/tty 2>/dev/null || true
    local _junk
	# перший прохід: зʼїсти все, що є зараз
    while IFS= read -r -s -n 10000 -t 0 _junk < /dev/tty; do :; done
	# коротка пауза — дати «підʼїхати» пізнім байтам, потім ще раз злити
    sleep 0.02 2>/dev/null || true
    while IFS= read -r -s -n 10000 -t 0 _junk < /dev/tty; do :; done
  }

  # Хелпер: дізнатися поточний рядок курсора (1..LINES) БЕЗ блокування stdin
  get_cursor_row() {
	# Надсилаємо DSR-запит у /dev/tty і читаємо відповідь теж з /dev/tty
    # Формат відповіді: ESC [ row ; col R
    local esc=$'\e' resp
	# Вивести запит позиції курсора; якщо не вийшло — тихо відмовляємось
    printf '%s[6n' "$esc" > /dev/tty 2>/dev/null || return 1
	# Прочитати до символу 'R' з невеликим таймаутом, щоб не блокуватися
    IFS= read -r -s -t 0.05 -d 'R' resp < /dev/tty || return 1
	# resp зараз містить щось на кшталт: ESC[<row>;<col
    resp=${resp#*[}                # прибрати ESC[
    printf '%d' "${resp%%;*}"      # вивести <row>
    return 0
  }

  # Хелпер: переконатися, що блок меню вміститься без скролу (НЕ блокує, м'який фолбек)
  ensure_space_for_block() {
    local need=$1
    local lines cur over
    lines=$(tput lines 2>/dev/null || echo 9999)
	# спробувати дізнатись поточний рядок; якщо не вдалось — просто нічого не робимо
    if cur=$(get_cursor_row 2>/dev/null); then
      over=$(( cur + need - 1 - lines ))
	  # піднятись на over рядків, аби намалювати меню без прокрутки
      (( over > 0 )) && tput cuu $over 2>/dev/null || true
    fi
    return 0
  }
  
  ensure_space_for_scroll_block() {
	local method=2
	
	if [[ "$method" == "1" ]]; then
      # 1) Верх майбутнього блоку — поточна позиція
      tput sc
      # 2) Додамо рівно total_lines порожніх рядків знизу (1 раз — це швидко й безпечно)
      for ((i=0; i<total_lines; i++)); do printf '\n'; done
      # 3) Повернемося у верх цього блоку і вже тут усе малюємо
      tput rc
	elif [[ "$method" == "2" ]]; then
	  # Без alt-screen: НЕ друкуємо жодного \n.
	  # Якщо не вистачає місця вниз — підсуваємо якір (курсор) вгору на дефіцит рядків.
	  local lines cur avail need deficit
	  lines=$(tput lines 2>/dev/null || echo 9999)
	  cur=$(get_cursor_row 2>/dev/null || echo 1)
	  need=$total_lines                      # header + видимі рядки списку + actions
	  avail=$(( lines - cur + 1 ))
	  deficit=$(( need - avail ))
	  if (( deficit > 0 )); then
		# рухаємо курсор вгору, не змінюючи вміст екрану (нічого не «стираємо» і не скролимо)
		tput cuu $deficit 2>/dev/null || printf '\e[%dA' "$deficit"
	  fi
	  tput sc  # заякорили верх нашого блоку
	fi
  }
  
  # Гарантоване відновлення стану та стирання лише нашого блоку
  cleanup() {
	# Підстраховка для set -u
    local _already=${cleaned:-0}
    local _total=${total_lines:-0}
    (( _already == 1 )) && return
    cleaned=1

    # спершу ЗЛИВАЄМО можливі «хвости» ESC-послідовностей, щоб вони не потрапили у шелл
    drain_tty_input
	
	if (( SCROLLING )); then
		# повернути повний регіон екрана, щоб безпечно стирати
		reset_region
	fi

    if (( alt_used == 1 )); then
	  # alt-screen сам поверне попередній екран БЕЗ слідів меню у scrollback
      leave_alt
    else
	  if (( SCROLLING )); then
		# стерти РІВНО наш блок, починаючи з базового рядка
		goto_row "$_base_row"
		if tput dl1 >/dev/null 2>&1; then
			local i
			for ((i=0; i<_total; i++)); do 
				tput dl1
			done
		else
			printf '\033[%dM' "$_total"   # CSI n M
		fi
	  else
		# стерти рівно наш блок БЕЗ залишення порожніх рядків (стиснути вгору)
		tput rc 2>/dev/null || true
		# Якщо є терм-можливість видаляти рядок (dl1) — користуємось нею (сумісніше)
		if tput dl1 >/dev/null 2>&1; then
			local i
			for ((i=0; i<_total; i++)); do
				tput dl1
			done
		else
			# CSI n M — delete n lines from cursor (майже всюди підтримується)
			printf '\033[%dM' "$_total"
		fi
	  fi
    fi

    # Відновити TTY і курсор
    [[ -n "$_stty_saved" ]] && stty "$_stty_saved" </dev/tty 2>/dev/null || true
	
	if (( SCROLLING )); then
		# повернути wrap, щоб термінал не лишився «без перенесення»
		printf '%s' "$_WRAP_ON"
	fi
	
	# курсор тепер стоїть на місці якоря; нічого не заважає подальшому виводу
    tput cnorm
    trap - INT TERM
  }
  
  # --- Хелпери маркерів ---
  is_marked() {
    local idx=$1 m
    for m in "${marked[@]}"; do
      [[ $m -eq $idx ]] && return 0
    done
    return 1
  }
  
  toggle_mark() {
    local idx=$1
    if is_marked "$idx"; then
      local new=() m
      for m in "${marked[@]}"; do
        [[ $m -ne $idx ]] && new+=("$m")
      done
      marked=("${new[@]}")
    else
      marked+=("$idx")
    fi
  }

  # --- Малювання (без повного clear) ---
  draw_line_content() {
    local i=$1
    local cursor="  "
    [[ $i -eq $selected ]] && cursor="> "

    # беремо підготовлений дисплей-текст, якщо item колонки увімкнені
    local text
    if (( _cols_enabled )); then
      text="${_disp[$i]}"
    else
      text="${_items[$i]}"
    fi

    if [[ "$multi" == "1" ]]; then
      if is_marked "$i"; then
        printf "%s☑️  %s" "$cursor" "$text"
      else
        printf "%s⬜  %s" "$cursor" "$text"
      fi
    else
      printf "%s%s" "$cursor" "$text"
    fi
  }


  draw_line() {
    local i=$1

	if (( SCROLLING )); then
		(( i < top || i >= top + view_rows )) && return
		local row=$(( _vtop_row + (i - top) ))
		goto_row "$row"
		# друкуємо контент, а потім чистимо хвіст рядка — менше миготіння
		draw_line_content "$i"
		erase_eol
	else
		tput rc
		# перейти до рядка i від початку БЛОКУ ПІСЛЯ header
		local offset=$(( header_lines + i ))
		(( offset > 0 )) && tput cud $offset
		tput el
		draw_line_content "$i"
	fi
  }

  # Панель дій: малюємо один рядок повністю
  draw_actions_line() {
    (( has_actions == 0 )) && return
	
	if (( SCROLLING )); then
		goto_row "$_agap_row";  erase_eol	# пустий відступ (замість "\n" — прямий перехід)
		goto_row "$_act_row";   erase_eol	# рядок кнопок
	else
		tput rc
		local offset=$(( header_lines + ${#_items[@]} ))
		(( offset > 0 )) && tput cud $offset
		tput el
    fi
	
	local i label bar=""
    for i in "${!_actions[@]}"; do
      label="${_actions[$i]}"
      if [[ $i -eq $action_selected ]]; then
        if [[ "$focus" == "actions" ]]; then
          bar+="⟪ ${label} ⟫  "		# фокус на кнопці
        else
          bar+="[ ${label} ]  "		# виділено, але без фокуса
        fi
      else
        bar+="  ${label}    "
      fi
    done

	if (( SCROLLING )); then
		printf "%s" "$bar"
	else
		printf "\n%s" "$bar"
	fi
  }

  draw_full() {
	if (( SCROLLING )); then
		# header: малюємо у свої абсолютні рядки
		if (( header_lines > 0 )); then
			local r h
			r=$_base_row
			for h in "${header_arr[@]}"; do
				goto_row "$r"; erase_eol; printf "%s" "$h"
				((r++))
			done
		fi
		# items: рівно видиме вікно [top, top+view_rows)
		local i end=$(( top + view_rows ))
		(( end > n_items )) && end=$n_items
		for ((i=top; i<end; i++)); do
			local row=$(( _vtop_row + (i - top) ))
			goto_row "$row"
			draw_line_content "$i"
			erase_eol
		done
	else
		tput rc
		# header
		if (( header_lines > 0 )); then
			local h
			for h in "${header_arr[@]}"; do
				tput el
				printf "%s\n" "$h"
			done
		fi
		# items
		local i
			for ((i=0; i<${#_items[@]}; i++)); do
			tput el
			draw_line_content "$i"
			printf "\n"
		done
	fi
  }
  
  # Synchronized Output (більшість терміналів підтримують; невідомі - ігнорують)
  sync_on(){  printf '\e[?2026h'; }  # почати «кадр»
  sync_off(){ printf '\e[?2026l'; }  # завершити «кадр»
  # швидкі ANSI (абсолютні переходи)
  goto_row(){ printf '\e[%d;1H' "$1"; }
  erase_eol(){ printf '\e[K'; }
  # Поставити/прибрати 2-символьний «жолоб» курсора в рядку i (без очистки рядка)
  set_cursor_at() {
    local i=$1 on=$2 row
    if (( SCROLLING )); then
      (( i < top || i >= top + view_rows )) && return
      row=$(( _vtop_row + (i - top) ))
      goto_row "$row"
    else
      tput rc
      local offset=$(( header_lines + i ))
      (( offset > 0 )) && tput cud $offset
    fi
    if (( on )); then printf "> "; else printf "  "; fi
  }
  # Лише прибрати «жолоб» у старому рядку — корисно ПЕРЕД скролом
  blank_cursor_at() {
    set_cursor_at "$1" 0
  }
  # Швидке переміщення курсора між двома видимими рядками без повного редраву
  cursor_swap_move() {
    local old=$1 new=$2
    blank_cursor_at "$old"
    set_cursor_at "$new" 1
  }

# --- Головна функція меню ---
function menu_choose() {
  
  local items_ref="" outvar="" multi=0 header=""
  local altscreen=""   # alt-screen
  local return_type="" index_base=""  # режим повернення (values|indices) і база індексу (0|1)
  local actions_ref="" actions=""     # джерело панелі дій: масив або список через кому/пробіли
  local actionvar=""                  # куди записати, що натиснулося
  local allow_null=""                 # дозволити OK з порожнім вибором
  local item_colsep="" item_showcols="" item_retcol="" item_colw="" item_colgap="" item_colpad=""	# Item columns

  for arg in "$@"; do
    case $arg in
      items=*)   items_ref="${arg#*=}" ;;
      outvar=*)  outvar="${arg#*=}" ;;
      multi=*)   multi="${arg#*=}" ;;
      allow_null=*) allow_null="${arg#*=}" ;;
      header=*)  header="${arg#*=}" ;;
	  # керування альтернативним екраном
      altscreen=*) altscreen="${arg#*=}" ;;		# altscreen=1|0|on|off|alt|main|auto
      alt=*)       altscreen="${arg#*=}" ;;		# синонім altscreen
      screen=alt)  altscreen="alt" ;;
      screen=main) altscreen="main" ;;
      # панель дій
      actions_ref=*) actions_ref="${arg#*=}" ;;
      actions=*)     actions="${arg#*=}" ;;
      actionvar=*)   actionvar="${arg#*=}" ;;
	  # режим повернення значень/індексів
      return=*)     return_type="${arg#*=}" ;;	# return=values|indices
      mode=indices) return_type="indices" ;;	# синонім
      indices=1)    return_type="indices" ;;	# синонім
      # база індексів (0 або 1)
      index_base=*) index_base="${arg#*=}" ;;
	  # item columns: розбиття кожного item на колонки
      item_colsep=*)	item_colsep="${arg#*=}" ;;     # роздільник колонок (дефолт: TAB)
      item_showcols=*)	item_showcols="${arg#*=}" ;;   # які колонки показувати (наприклад: "2,3" або "2-" або "2-4")
      item_retcol=*)	item_retcol="${arg#*=}" ;;     # з якої колонки повертати значення (1-баз.)
      item_colw=*)		item_colw="${arg#*=}" ;;       # ширини видимих колонок, CSV (0 = авто/без обрізки)
      item_colgap=*)	item_colgap="${arg#*=}" ;;     # відступ між видимими колонками (символів)
      item_colpad=*)	item_colpad="${arg#*=}" ;;     # 1|0 — чи добивати пробілами до ширини

    esac
  done

  if [[ -z "$items_ref" && -z "$outvar" ]]; then
	echo "❌  Не вказано items=<array> і outvar=<var>" >&2
	return 1
  elif [[ -z "$items_ref" ]]; then
	echo "❌  Не вказано items=<array>" >&2
	return 1
  elif [[ -z "$outvar" ]]; then
	echo "❌  Не вказано outvar=<var>" >&2
	return 1
  fi

  local -n _items="$items_ref"	# масив з пунктами
  local -n _out="$outvar"		# змінна/масив для результату

  # --- Стан ---
  local selected=0
  local marked=()
  local cleaned=0   			# щоб cleanup не спрацьовував двічі
  # прапор переривання та статус завершення
  local _sigint=0
  local _aborted=0
  local _cancelled=0			# Cancel: скасувати поточне меню, (return RC_CANCEL>0)
  local _explicit_empty=0		# Exit: свідомо порожній результат (return RC_EXIT>0)
  local _last_action=""			# що саме натиснули
  # коди повернення (можна перевизначити через env)
  local RC_OK=0
  local RC_CANCEL=${MENU_CHOOSE_CANCEL_RC:-2}
  local RC_EXIT=${MENU_CHOOSE_EXIT_RC:-3}
  local RC_ABORT=${MENU_CHOOSE_ABORT_RC:-130}
  # налаштовний таймаут читання (щоб read прокидався й бачив _sigint)
  local READ_T=${MENU_CHOOSE_READ_T:-0.05}
  # фокусування: "list" або "actions"
  local focus="list"
  local action_selected=0
  # Керування автоперенесенням (wrap) на час роботи меню
  local _WRAP_OFF _WRAP_ON
  _WRAP_OFF=$(tput rmam 2>/dev/null) || _WRAP_OFF=$'\e[?7l'
  _WRAP_ON=$(tput smam 2>/dev/null)  || _WRAP_ON=$'\e[?7h'
  
  # Налаштування повернення: за замовчуванням values; базу беремо з env або 0
  local out_mode
  if [[ -n "$return_type" ]]; then
    case "${return_type,,}" in
      indices|index|idx) out_mode="indices" ;;
      *)                 out_mode="values"  ;;
    esac
  else
    out_mode="values"
  fi
  # Початковий індекс
  local idx_base
  if [[ -n "$index_base" ]]; then
    [[ "$index_base" == "1" ]] && idx_base=1 || idx_base=0
  else
    idx_base=${MENU_CHOOSE_INDEX_BASE:-0}
    [[ "$idx_base" == "1" ]] || idx_base=0
  fi
  
  # allow_null: OK може повернути порожній вибір (лише для multi=1)
  if [[ -z "$allow_null" ]]; then
    allow_null="${MENU_CHOOSE_ALLOW_NULL:-1}"
  fi
  local allow_empty
  case "${allow_null,,}" in
    1|on|true|yes) allow_empty=1 ;;
    0|off|false|no) allow_empty=0 ;;
    *) allow_empty=${MENU_CHOOSE_ALLOW_NULL:-1}; [[ "$allow_empty" == "1" ]] || allow_empty=0 ;;
  esac
  
  ######### Item COLUMNS: конфіг за замовчуванням #########
  # >>> COLUMNS: конфіг за замовчуванням
  local _cols_enabled=0
  local _item_colsep
  local -a _show_idx=()   # 1-базові індекси видимих колонок
  local -a _item_colw_arr=()   # ширини для видимих колонок (у тій же послідовності)
  local _gap=${item_colgap:-2}
  local _pad
  [[ -n "$item_colpad" ]] && _pad=$item_colpad || _pad=0

  # роздільник: дефолт — TAB; підтримка \t
  if [[ -z "$item_colsep" || "$item_colsep" == '\t' || "$item_colsep" == '\\t' ]]; then
    _item_colsep=$'\t'
  else
    _item_colsep="$item_colsep"
  fi

  # вмикаємо режим колонок, якщо задано item_showcols або item_retcol або item_colw
  if [[ -n "$item_showcols" || -n "$item_retcol" || -n "$item_colw" ]]; then
    _cols_enabled=1
  fi

  # item_retcol: за замовчуванням 1 (прихований id/name)
  local _item_retcol=${item_retcol:-1}
  ((_item_retcol<1)) && _item_retcol=1

  # розбір item_showcols:
  # - "2,3"     → 2 3
  # - "2-"      → 2..∞
  # - "2-4"     → 2 3 4
  if (( _cols_enabled )); then
    local tok
    if [[ -z "$item_showcols" ]]; then
      # за замовчуванням: ховаємо item_retcol, показуємо решту (типовий кейс "1 приховано → показ 2-")
      item_showcols="$(( _item_retcol + 1 ))-"
    fi
    # парсимо item_showcols у _show_idx
    local IFS=',$ '
    for tok in $item_showcols; do
      if [[ "$tok" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}
        ((a<1)) && a=1
        for ((i=a;i<=b;i++)); do _show_idx+=("$i"); done
      elif [[ "$tok" =~ ^([0-9]+)-$ ]]; then
        local a=${BASH_REMATCH[1]}
        ((a<1)) && a=1
        # верхню межу не знаємо наперед — залишимо позначку -1 (означає "до кінця")
        _show_idx+=("$a-")
      elif [[ "$tok" =~ ^([0-9]+)$ ]]; then
        _show_idx+=("${BASH_REMATCH[1]}")
      fi
    done

    # ширини для видимих колонок (CSV, у тій самій кількості; 0=нема обмеження)
    if [[ -n "$item_colw" ]]; then
      local IFS=',$ '
      read -r -a _item_colw_arr <<< "$item_colw"
    fi
  fi

  # препроцес: побудувати відображуваний текст кожного item і значення для повернення з item_retcol
  # збережемо у двох паралельних масивах, щоб draw_* лише брав готові рядки
  local -a _disp=()   # те, що показуємо
  local -a _retv=()   # те, що повертаємо (значення з item_retcol)

  if (( _cols_enabled )); then
    # утиліта: обрізати/падити до ширини
    _fmt_cell() {
      local s="$1" w="$2"
      # без фіксованої ширини: просто повернути
      (( w<=0 )) && { printf '%s' "$s"; return; }
      local len=${#s}
      if (( len > w )); then
        # просте обрізання (без урахування багатобайтових/ANSI; можна доробити пізніше)
        printf '%s' "${s:0:w}"
      else
        if (( _pad == 1 )); then
          printf '%-*s' "$w" "$s"
        else
          printf '%s' "$s"
        fi
      fi
    }

    # геп між колонками
    local _gapstr
    printf -v _gapstr '%*s' "$_gap" ''

    local i line
    for i in "${!_items[@]}"; do
      line="${_items[$i]}"
      # розбити на колонки
      local IFS="$_item_colsep"
      read -r -a __cols <<< "$line"
      local n=${#__cols[@]}
      # значення для повернення
      local rix=$((_item_retcol-1))
      local rval=""
      if (( rix>=0 && rix<n )); then
        rval="${__cols[$rix]}"
      else
        # якщо item_retcol не існує — фолбек на весь рядок
        rval="$line"
      fi
      _retv+=("$rval")

      # побудувати видиму частину
      local vis=() want i2 last_range_start=-1
      for want in "${_show_idx[@]}"; do
        if [[ "$want" == *- ]]; then
          last_range_start="${want%-}"
          # додамо весь діапазон від start до n
          for ((i2=last_range_start; i2<=n; i2++)); do
            vis+=("$i2")
          done
        else
          vis+=("$want")
        fi
      done
      # унікалізуємо та відкидаємо ті, що поза діапазоном
      local v uniq=() seen=()
      for v in "${vis[@]}"; do
        (( v>=1 && v<=n )) || continue
        if [[ -z "${seen[$v]+_}" ]]; then
          uniq+=("$v"); seen[$v]=1
        fi
      done
      vis=("${uniq[@]}")

      # застосовуємо ширини
      local cells=() cw idx j
      for j in "${!vis[@]}"; do
        idx=$(( vis[j]-1 ))
        cw=0
        if (( j < ${#_item_colw_arr[@]} )); then
          cw=${_item_colw_arr[$j]}
          [[ -z "$cw" ]] && cw=0
        fi
        cells+=( "$(_fmt_cell "${__cols[$idx]}" "$cw")" )
      done
      # зліпити cells розподільником _gapstr
	  if ((${#cells[@]})); then
		if ((${#cells[@]} == 1)); then
			_disp+=( "${cells[0]}" )
		else
			local first="${cells[0]}"
			local rest=("${cells[@]:1}")
			# додати префікс-gap до кожного зі "стовпців, що лишилися"
			printf -v joined '%s' "$first" "${rest[@]/#/${_gapstr}}"
			_disp+=( "$joined" )
		fi
	  fi

    done
  fi
  
  ######### Item COLUMNS: END #########

  # Header (підтримка багаторядкового заголовка)
  local header_lines=0
  local header_arr=()
  if [[ -n "$header" ]]; then
    mapfile -t header_arr <<< "$header"
    header_lines=${#header_arr[@]}
  fi
  
  # Панель дій (actions)
  local -a _actions=()
  if [[ -n "$actions_ref" ]]; then
    local -n _act="$actions_ref"
    _actions=("${_act[@]}")
  fi
  if [[ -n "$actions" ]]; then
    # підтримуємо як коми, так і пробіли
    local IFS=$' ,'
    read -r -a _tmp_actions <<< "$actions"
    if ((${#_tmp_actions[@]})); then
      _actions+=("${_tmp_actions[@]}")
    fi
  fi
  local has_actions=0
  local actions_lines=0
  if (( ${#_actions[@]} > 0 )); then
	has_actions=1
	actions_lines=2
  fi
  
  # Total lines
  local total_lines=$(( header_lines + ${#_items[@]} + actions_lines ))
  
  # Визначення потреби у scroll
  local need_scroll=0
  local n_items=${#_items[@]}
  local term_h=$(tput lines 2>/dev/null || echo 40)

  # Скільки рядків між header і actions доступно в екрані
  local screen_rows=$(( term_h - header_lines - actions_lines ))
  (( screen_rows < 1 )) && screen_rows=1

  # Чи потрібен скрол видимого вікна (список не влазить)
  local need_scroll=0
  (( n_items > screen_rows )) && need_scroll=1
  
  local SCROLLING=0
  (( need_scroll )) && SCROLLING=1
  
  if (( SCROLLING )); then
  
	# Скільки рядків зі списку реально видно між header та панеллю дій
	local view_rows=$(( term_h - header_lines - actions_lines ))
	(( view_rows < 1 )) && view_rows=1
	(( view_rows > n_items )) && view_rows=$n_items

	# перший видимий індекс (верх списку) та його максимум
	local top=0
	local max_top=$(( n_items - view_rows ))
	(( max_top < 0 )) && max_top=0

	# Скільки реально малюємо рядків → стільки й стираємо в cleanup
	local total_lines=$(( header_lines + view_rows + actions_lines ))
  
  fi

  # альтернативний екран
  # Якщо не вказано, тягнемо з env або ставимо auto
  if [[ -z "$altscreen" ]]; then
    altscreen="${MENU_CHOOSE_ALTSCREEN:-auto}"
  fi
  local use_alt alt_used=0
  # нормалізація значення
  case "${altscreen,,}" in
    1|on|true|yes|alt)   use_alt=1 ;;
    0|off|false|no|main) use_alt=0 ;;
    auto|*)              use_alt="$need_scroll" ;;
  esac

  # зберегти попередні налаштування TTY
  local _stty_saved=""
  if _stty_saved=$(stty -g </dev/tty 2>/dev/null); then
    # приглушити ^C і пропустити ^Q до скрипта (вимкнути XON/XOFF)
    stty -echoctl -ixon </dev/tty 2>/dev/null || true
  fi
  
  # --- Керування курсором та очищення області меню ---
  tput civis	# сховати системний курсор
  
  # поточний чи альтернативний екран
  if (( SCROLLING )); then
    if ! enter_alt; then
		ensure_space_for_scroll_block
    else
      tput sc	# В alt-screen і так працюємо на «чистому полотні»
    fi
  else
    if ! enter_alt; then
	  # забезпечуємо місце для блоку, щоб НЕ було прокрутки (і menu не йшло у scrollback)
      ensure_space_for_block "$total_lines"
    fi
    tput sc		# зберегти позицію курсора як "якір" верхнього рядка меню
  fi
  
  # Абсолютні координати viewport (для scroll-region)
  if (( SCROLLING )); then
  
	# Якір (верх усього блоку меню) – абсолютний рядок екрана (1-баз.)
	local _base_row
	_base_row=$(get_cursor_row 2>/dev/null || echo 1)

	# межі видимого ВІКНА СПИСКУ (між header та actions), абсолютні рядки
	local _vtop_row=$(( _base_row + header_lines ))
	local _vbot_row=$(( _vtop_row + view_rows - 1 ))

	# рядок «порожнього відступу» перед actions і рядок самих кнопок
	local _agap_row=$(( _vbot_row + 1 ))
	local _act_row=$(( _vbot_row + 2 ))

	# встановити/скинути scroll-region рівно на вікно списку
	set_region(){ printf '\e[%d;%dr' "$_vtop_row" "$_vbot_row"; }
	reset_region(){ printf '\e[r'; }

	# скролинг регіону на 1 рядок (без зачепу header/actions)
	scroll_region_up_one(){   goto_row "$_vtop_row"; printf '\eM'; }  # RI: вставка зверху
	scroll_region_down_one(){ goto_row "$_vbot_row"; printf '\eD'; }  # IND: вставка знизу

	# активувати регіон списку
	set_region

	# вимкнути wrap на час роботи меню (щоб не було автопереносу)
	printf '%s' "$_WRAP_OFF"
  
  fi

  # INT лише ставить прапорець, цикл коректно виходить, потім cleanup чистить буфери.
  trap '_sigint=1; _aborted=1' INT
  trap cleanup TERM

  # Початковий рендер (без глобального clear)
  sync_on
  
  draw_full
  draw_actions_line
  
  sync_off

  # --- Обробка клавіш ---
  while true; do
    
	# read: -r сирий бекслеш, -s без ехо, -n1 один символ, -t таймаут
	# якщо «тикнув» Ctrl+C — trap виставить _sigint=1 і read прокинеться максимум за READ_T
    [[ $_sigint -eq 1 ]] && break
    if ! read -rsN1 -t "$READ_T" key; then
	  # таймаут — перевіримо сигнал і далі крутимось
      continue
    fi
    [[ $_sigint -eq 1 ]] && break

    # якщо термінал все ж передав «сирий» Ctrl+C (ETX)
    if [[ $key == $'\x03' ]]; then _sigint=1; _aborted=1; break; fi
	
	# Ctrl+Q (DC1) — швидкий вихід
	if [[ $key == $'\x11' ]]; then
		_explicit_empty=1
		break
	fi

    case "$key" in
		$'\x1b') # escape / arrows / Home / End
			
			# дочитуємо можливі коди клавіш (неблокуюче)
			read -rsn2 -t 0.001 key2 || key2=""
			
			# якщо «голий» Esc — трактуємо як скасування
			if [[ -z $key2 ]]; then _cancelled=1; break; fi
			
			# деякі термінали шлють Home/End як трисимвольні послідовності типу "[1~", "[4~", "[7~", "[8~"
			read -rsn1 -t 0.0005 key3 || key3=""
			local seq="${key2}${key3}"
			
			# Спочатку перехоплюємо Home/End (накриває більшість варіацій: [H, OH, [1~,[7~ і [F, OF, [4~,[8~)
			case "$seq" in
				"[H"|"OH"|"[1~"|"[7~")   # HOME
					if [[ "$focus" == "actions" ]]; then
					  action_selected=0
					  draw_actions_line
					else
					  local old=$selected
					  selected=0
					  if (( SCROLLING )); then
						top=0
						draw_full
						draw_actions_line
					  else
						draw_line "$old"
						draw_line "$selected"
					  fi
					fi
					continue
					;;
				"[F"|"OF"|"[4~"|"[8~")   # END
					if [[ "$focus" == "actions" ]]; then
					  action_selected=$(( ${#_actions[@]} - 1 ))
					  (( action_selected < 0 )) && action_selected=0
					  draw_actions_line
					else
					  local old=$selected
					  selected=$(( n_items - 1 ))
					  if (( SCROLLING )); then
						top=$max_top
						draw_full
						draw_actions_line
					  else
						draw_line "$old"
						draw_line "$selected"
					  fi
					fi
					continue
					;;
			esac
			
			# Якщо не Home/End — обробляємо стрілки, Shift-Tab
			case "$key2" in
				"[A") # ↑
					if [[ "$focus" == "actions" ]]; then
					  # з панелі дій повертаємо фокус у список
					  focus="list"
					  draw_actions_line
					else
					  
					  if (( SCROLLING )); then
						
						local old=$selected
						
						if (( selected > 0 )); then
						  ((selected--))
						  
						  if (( selected < top )); then
							
							blank_cursor_at "$old" # ПЕРЕД скролом прибираємо '>' у старому рядку, щоб він не «їхав» у кадрі скролу
							((top--))
							scroll_region_up_one
							goto_row "$_vtop_row"; draw_line_content "$top"; erase_eol	# новий верхній елемент
							set_cursor_at "$selected" 1	# ставимо курсор вже в новому місці
						  
						  else
							
							sync_on
							draw_line "$old"
							if (( old != selected )); then
							  draw_line "$selected"
							fi
							sync_off
						  
						  fi
						
						else
						  
						  # wrap: з першого елемента одразу на останній
						  selected=$(( n_items - 1 ))
						  top=$max_top
						  draw_full
						  draw_actions_line
						  
						fi
					  
					  else
						
						local old=$selected
						((selected--))
						((selected<0)) && selected=$(( n_items - 1 ))

						sync_on
						# спочатку знімаємо підсвітку зі старого
						draw_line "$old"
						# потім малюємо новий виділений
						if (( old != selected )); then
						  draw_line "$selected"
						fi
						sync_off
					  
					  fi
					  
					fi
					;;
				"[B") # ↓
					if [[ "$focus" == "list" ]]; then
					  if (( SCROLLING )); then
						if (( selected < n_items - 1 )); then
						  local old=$selected
						  ((selected++))
						  if (( selected >= top + view_rows )); then
							# ПЕРЕД скролом прибираємо '>' у старому рядку
							blank_cursor_at "$old"
							
							((top++))
							scroll_region_down_one
							local idx=$(( top + view_rows - 1 ))

							# новий нижній елемент
							goto_row "$_vbot_row"; draw_line_content "$idx"; erase_eol

							# ставимо курсор у новому місці
							set_cursor_at "$selected" 1
						  else
							sync_on
							draw_line "$old"
							if (( old != selected )); then
							  draw_line "$selected"
							fi
							sync_off
						  fi
						else
							if (( has_actions )); then
								# кінець списку → в панель дій
								focus="actions"
								draw_actions_line
							else
								# wrap: кінець списку → на початок
								local old=$selected
								selected=0
								top=0
								draw_full
								draw_actions_line
							fi
						fi
					  else
						# рухаємося вниз ПО списку, а на панель дій переходимо лише якщо вже на останньому елементі
						if (( selected < n_items - 1 )); then
						  local old=$selected
						  ((selected++))
						  sync_on
						  draw_line "$old"
						  if (( old != selected )); then
							draw_line "$selected"
						  fi
						  sync_off
						else
						  if (( has_actions )); then
							# кінець списку → в панель дій
							focus="actions"
							draw_actions_line
						  else
							# wrap: кінець списку → на початок
							local old=$selected
							selected=0
							draw_line "$old"
							draw_line "$selected"
						  fi
						fi
					  fi
					else
					  # focus == actions: стрілка ↓ → назад у список (wrap крізь actions)
					  focus="list"
					  draw_actions_line
					fi
					;;
				"[C") # → (праворуч)
					if [[ "$focus" == "actions" && $has_actions -eq 1 ]]; then
					  ((action_selected++))
					  ((action_selected>=${#_actions[@]})) && action_selected=0
					  draw_actions_line
					fi
					;;
				"[D") # ← (ліворуч)
					if [[ "$focus" == "actions" && $has_actions -eq 1 ]]; then
					  ((action_selected--))
					  ((action_selected<0)) && action_selected=$(( ${#_actions[@]} - 1 ))
					  draw_actions_line
					fi
					;;
				"[Z") # Shift-Tab (часто так кодується)
					if [[ $has_actions -eq 1 ]]; then
					  if [[ "$focus" == "actions" ]]; then
						focus="list"
					  else
						focus="actions"
					  fi
					  draw_actions_line
					fi
					;;
			esac
			;;
		$'\t') # Tab
			if [[ $has_actions -eq 1 ]]; then
			  if [[ "$focus" == "actions" ]]; then
				focus="list"
			  else
				focus="actions"
			  fi
			  draw_actions_line
			fi
			# важливо: нічого більше в цій ітерації не робимо
			continue
			;;
		" ") # Пробіл для multi
			if [[ "$multi" == "1" && "$focus" == "list" ]]; then
			  toggle_mark "$selected"
			  draw_line "$selected"
			fi
			;;
		$'\r'|$'\n')  # Enter
			if (( has_actions )); then
			  # Завжди виконуємо ВИБРАНУ кнопку з панелі, незалежно від фокуса
			  local act="${_actions[$action_selected]}"
			  _last_action="$act"
			  local act_lc="${act,,}"
			  case "$act_lc" in
				ok|apply|save|done|confirm)
				  # OK: підтвердження вибору
				  if [[ "$multi" == "1" ]]; then
					if (( ${#marked[@]} == 0 )); then
					  (( allow_empty == 0 )) && marked=("$selected")
					fi
				  else
					marked=("$selected")
				  fi
				  break
				  ;;
				cancel|esc|clear|none|no)
				  # CANCEL: скасувати поточне меню (ненульовий rc)
				  _cancelled=1
				  break
				  ;;
				exit|quit)
				  # EXIT: свідомо порожній результат (ненульовий rc для EXIT)
				  marked=()
				  _explicit_empty=1
				  break
				  ;;
				*)
				  # дефолт — OK
				  if [[ "$multi" == "1" ]]; then
					if (( ${#marked[@]} == 0 )); then
					  (( allow_empty == 0 )) && marked=("$selected")
					fi
				  else
					marked=("$selected")
				  fi
				  break
				  ;;
			  esac
			else
			  # Нема панелі actions — класична логіка: прийняти вибір списку
			  _last_action="ok"
			  if [[ "$multi" == "1" ]]; then
				if (( ${#marked[@]} == 0 )); then
				  (( allow_empty == 0 )) && marked=("$selected")
				fi
			  else
				marked=("$selected")
			  fi
			  break
			fi
			;;
		$'\x01')  # Ctrl+A — Select All / Toggle All (працює лише в multi=1)
			if [[ "$multi" == "1" && "$focus" == "list" ]]; then
			  # якщо вже все виділено — скинь, інакше — виділи все
			  if (( ${#marked[@]} == n_items )); then
				marked=()
			  else
				marked=()
				# заповнюємо індексами 0..n_items-1
				for ((i=0; i<n_items; i++)); do
				  marked+=("$i")
				done
			  fi

			  # Оновити відмальовку поточного вікна
			  if (( SCROLLING )); then
				end=$(( top + view_rows ))
				(( end > n_items )) && end=$n_items
				for ((i=top; i<end; i++)); do
				  draw_line "$i"
				done
			  else
				for ((i=0; i<n_items; i++)); do
				  draw_line "$i"
				done
			  fi
			  # Підсвітити поточний рядок і перемалювати панель дій
			  draw_line "$selected"
			  draw_actions_line
			fi
			;;
    esac
  done

  # Результат
  if (( _aborted == 0 && _cancelled == 0 )); then
    # якщо Exit/None або просто порожній вибір — віддати порожньо
    if (( _explicit_empty == 1 )) || (( ${#marked[@]} == 0 )); then
      if [[ "$multi" == "1" ]]; then
        _out=()
      else
        printf -v _out "%s" ""
      fi
    else
      if [[ "$out_mode" == "indices" ]]; then
        # повертаємо індекси (з урахуванням бази idx_base)
        if [[ "$multi" == "1" ]]; then
          _out=()
          local i
          for i in "${marked[@]}"; do
            if (( idx_base == 1 )); then
              _out+=($(( i + 1 )))
            else
              _out+=($i)
            fi
          done
        else
          local i="${marked[0]}"
          if (( idx_base == 1 )); then
            printf -v _out "%d" $(( i + 1 ))
          else
            printf -v _out "%d" "$i"
          fi
        fi
      else
        
		# класичний режим: повертаємо значення
        if [[ "$multi" == "1" ]]; then
          _out=()
          local idx
          for idx in "${marked[@]}"; do
            if (( _cols_enabled )); then
              _out+=("${_retv[$idx]}")     # ← значення з item_retcol
            else
              _out+=("${_items[$idx]}")
            fi
          done
        else
          if (( _cols_enabled )); then
            printf -v _out "%s" "${_retv[${marked[0]}]}"
          else
            printf -v _out "%s" "${_items[${marked[0]}]}"
          fi
        fi		
		
      fi
	
	fi
  fi
  
  # визначаємо останню дію якщо явно не вказана
  if [[ -z "$_last_action" ]]; then
	if   (( _aborted )); then 			_last_action="abort";
	elif (( _cancelled )); then 		_last_action="esc";
	elif (( _explicit_empty )); then	_last_action="exit";
	fi
  fi
  
  # якщо просили — повідомляємо, що саме натиснули
  if [[ -n "$actionvar" ]]; then
    # дефолт — якщо користувач просто підтвердив вибір у списку
    local _act_val="${_last_action:-ok}"
    printf -v "$actionvar" "%s" "$_act_val"
  fi
  
  # Акуратний вихід
  cleanup
  
  if   (( _aborted )); then 		return "$RC_ABORT";		# Ctrl+C
  elif (( _cancelled )); then 		return "$RC_CANCEL";	# Cancel
  elif (( _explicit_empty )); then	return "$RC_EXIT";		# Exit (чистий вихід)
  else                          	return "$RC_OK";        # OK
  fi
}
