#!/bin/bash

POOL_NAME=$1

if [ -z "$POOL_NAME" ]; then
  echo "Вкажіть ім'я пулу, наприклад: ./restart_php_pool.sh nlime"
  exit 1
fi

echo "Перезапуск PHP-FPM пулу: $POOL_NAME"

sudo pkill -f "php-fpm: pool $POOL_NAME"

echo "Готово. Процеси пулу $POOL_NAME мають перезапуститись автоматично."
