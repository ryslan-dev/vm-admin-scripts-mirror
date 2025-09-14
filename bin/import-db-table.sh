#!/bin/bash

# ✅ Значення за замовчуванням для CSV
DELIMITER=","
ENCLOSED_BY="\""
ESCAPED_BY="\""
LINE_TERMINATED_BY="\n"
COL_NAMES=0
ON_DUPLICATE_KEY=""
LIMIT_ROWS=""
NEW_TABLE_NAME=""
SKIP_ERRORS=false

# ✅ Парсимо аргументи key=value
for ARG in "$@"; do
    case $ARG in
        dbname=*) DB_NAME="${ARG#*=}" ;;
        table=*) TABLE_NAME="${ARG#*=}" ;;
        file=*) DATA_FILE="${ARG#*=}" ;;
        format=*) FORMAT="${ARG#*=}" ;;
        delimiter=*) DELIMITER="${ARG#*=}" ;;
        enclosed=*) ENCLOSED_BY="${ARG#*=}" ;;
        escaped=*) ESCAPED_BY="${ARG#*=}" ;;
        line_terminated=*) LINE_TERMINATED_BY="${ARG#*=}" ;;
        col_names=*) COL_NAMES="${ARG#*=}" ;;
        on_duplicate_key_update=*) ON_DUPLICATE_KEY="ON DUPLICATE KEY UPDATE ${ARG#*=}" ;;
        limit_rows=*) LIMIT_ROWS="${ARG#*=}" ;;
        new_table=*) NEW_TABLE_NAME="${ARG#*=}" ;;
        skip_errors=*) SKIP_ERRORS=true ;;
        *)
            echo "❌ Невідомий аргумент: $ARG"
            echo "📖 Використання: $0 dbname=DB_NAME table=TABLE_NAME file=DATA_FILE format=FORMAT [інші параметри]"
            exit 1
            ;;
    esac
done

# ✅ Перевірка обов’язкових параметрів
if [ -z "$DB_NAME" ] || [ -z "$TABLE_NAME" ] || [ -z "$DATA_FILE" ] || [ -z "$FORMAT" ]; then
    echo "❌ Необхідно вказати dbname=, table=, file=, format="
    echo "📖 Використання: $0 dbname=DB_NAME table=TABLE_NAME file=DATA_FILE format=FORMAT [інші параметри]"
    exit 1
fi

# ✅ Перевірка файлу
if [ ! -f "$DATA_FILE" ]; then
    echo "❌ Файл $DATA_FILE не існує."
    exit 2
fi

# 🧹 cleanup
cleanup() {
    if [ -n "${TMP_FILE:-}" ] && [ -f "${TMP_FILE:-}" ]; then
        rm -f "$TMP_FILE"
        echo "🧹 Тимчасовий файл $TMP_FILE видалено."
    fi
    if [ -n "${MYSQL_CNF:-}" ] && [ -f "${MYSQL_CNF:-}" ]; then
        rm -f "$MYSQL_CNF"
        echo "🧹 Тимчасовий конфіг-файл MySQL видалено."
    fi
}
trap cleanup EXIT


# ✅ Запит користувача БД і пароль
read -p "👤 Введіть ім'я користувача MariaDB/MySQL: " DB_USER
read -s -p "🔑 Введіть пароль користувача $DB_USER: " DB_PASS
echo

# ✅ Створюємо тимчасовий конфіг для mysql (щоб пароль не видно було в процесах)
MYSQL_CNF=$(mktemp)
chmod 600 "$MYSQL_CNF"
cat > "$MYSQL_CNF" <<EOF
[client]
user=$DB_USER
password=$DB_PASS
local-infile=1
EOF

# ✅ Якщо вказано нову таблицю — замінюємо ім'я
if [ -n "$NEW_TABLE_NAME" ]; then
    TABLE_NAME="$NEW_TABLE_NAME"
fi

mysql_cmd() {
    mysql --defaults-extra-file="$MYSQL_CNF" -D "$DB_NAME" -e "$1"
}

# ✅ Для формату CSV
if [ "$FORMAT" = "csv" ]; then
    echo "📥 Імпорт CSV у $DB_NAME.$TABLE_NAME..."

    # Перевірка чи існує таблиця
    TABLE_EXISTS=$(mysql_cmd "SHOW TABLES LIKE '$TABLE_NAME';" | grep "$TABLE_NAME")

    if [ -z "$TABLE_EXISTS" ]; then
        echo "📦 Таблиця $TABLE_NAME не існує. Створюємо..."
    
        # Витягнути заголовок CSV для створення колонок
        HEADER=$(head -n 1 "$DATA_FILE")
        IFS="$DELIMITER" read -ra COLUMNS <<< "$HEADER"

        SQL_CREATE="CREATE TABLE \`$TABLE_NAME\` ("
        for COL in "${COLUMNS[@]}"; do
            COL_CLEAN=$(echo "$COL" | tr -d '"' | tr -d "'" | xargs)
            SQL_CREATE+="\`$COL_CLEAN\` TEXT,"
        done
        SQL_CREATE=${SQL_CREATE%,}
        SQL_CREATE+=");"

        mysql_cmd "$SQL_CREATE"
        if [ $? -eq 0 ]; then
            echo "✅ Таблиця $TABLE_NAME створена."
        else
            echo "❌ Не вдалося створити таблицю."
            exit 3
        fi
    else
        echo "✅ Таблиця $TABLE_NAME вже існує."
    fi
	
    # Якщо є ліміт рядків — створюємо тимчасовий файл з частиною даних
    if [[ -n "$LIMIT_ROWS" && "$LIMIT_ROWS" =~ ^[0-9]+$ && "$LIMIT_ROWS" -gt 0 ]]; then
        TMP_FILE="/tmp/$(basename "$DATA_FILE").tmp"
        echo "📦 Створюємо тимчасовий файл з $LIMIT_ROWS рядками: $TMP_FILE"
        head -n $((LIMIT_ROWS + COL_NAMES)) "$DATA_FILE" > "$TMP_FILE"
        DATA_FILE="$TMP_FILE"
    fi

    # ✅ Формуємо SQL
    SQL="
    LOAD DATA LOCAL INFILE '$(realpath "$DATA_FILE")'
    INTO TABLE \`$TABLE_NAME\`
    FIELDS TERMINATED BY '$DELIMITER'
    ENCLOSED BY '$ENCLOSED_BY'
    ESCAPED BY '$ESCAPED_BY'
    LINES TERMINATED BY '$LINE_TERMINATED_BY'
    "

    if [ "${COL_NAMES:-1}" -eq 1 ]; then
        SQL+="IGNORE 1 LINES "
    fi

    if [ -n "$ON_DUPLICATE_KEY" ]; then
		SQL+=" $ON_DUPLICATE_KEY"
	fi


    # ✅ Виконання імпорту
    echo "⚙️ Виконання імпорту..."
    
	if [ "$SKIP_ERRORS" = true ]; then
        mysql_cmd "$SQL" || echo "⚠️ Деякі рядки не вдалося вставити, але імпорт продовжено."
    else
        mysql_cmd "$SQL"
    fi

    if [ $? -eq 0 ]; then
        echo "✅ Імпорт завершено успішно!"
    else
        echo "❌ Помилка під час імпорту."
    fi
else
    echo "❌ Формат '$FORMAT' ще не підтримується."
    exit 4
fi
