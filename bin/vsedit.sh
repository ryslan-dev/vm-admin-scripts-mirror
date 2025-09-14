#!/bin/bash

if [ -z "$1" ]; then
    echo "❌ Вкажи шлях до файлу: vsed /etc/...."
    exit 1
fi

TMP_FILE=/tmp/.vsed_tmp_$$
FILE="$1"

echo "🔄 Копіюю $FILE у тимчасовий файл..."
if sudo cp "$FILE" "$TMP_FILE" && sudo chown "$USER":"$USER" "$TMP_FILE"; then
    echo "📝 Відкриваю файл у VS Code..."
    code --wait "$TMP_FILE"
    echo "⬆️ Зберігаю зміни назад у $FILE..."
    if sudo cp "$TMP_FILE" "$FILE"; then
        echo "✅ Файл оновлено: $FILE"
    else
        echo "❌ Не вдалося скопіювати назад. Перевір права."
    fi
    rm -f "$TMP_FILE"
else
    echo "❌ Не вдалося створити тимчасову копію. Можливо, немає доступу."
fi
