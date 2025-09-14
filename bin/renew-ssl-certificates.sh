#!/bin/bash

set -e

DRY_RUN=false

# Обробка аргументів
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    *)
      echo "❌ Невідомий аргумент: $arg"
      exit 1
      ;;
  esac
done

if $DRY_RUN; then
  echo "🔄 Виконуємо тестове оновлення сертифікатів (dry-run)..."
  sudo certbot renew --dry-run --quiet
else
  echo "🔄 Починаємо оновлення сертифікатів Certbot..."
  sudo certbot renew --quiet
fi

STATUS=$?

if [[ $STATUS -ne 0 ]]; then
  echo "❌ Помилка оновлення сертифікатів Certbot (код $STATUS)"
  exit $STATUS
fi

if ! $DRY_RUN; then
  echo "✅ Сертифікати оновлено або залишились актуальними."
  echo "🔁 Перевірка конфігурації NGINX..."

  if sudo nginx -t; then
    echo "✅ Конфігурація NGINX валідна. Перезавантажуємо NGINX..."
    sudo systemctl reload nginx
    echo "✅ NGINX перезавантажено успішно."
  else
    echo "❌ Помилка у конфігурації NGINX. Перезавантаження скасовано."
    exit 1
  fi
else
  echo "ℹ️ Тестове оновлення сертифікатів завершено."
fi
