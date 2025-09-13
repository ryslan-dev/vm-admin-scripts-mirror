#!/bin/bash

set -e

# Параметри за замовчуванням
CERT_NAME=""
DOMAIN=""
ALIASES=()
RELOAD_NGINX=false

# Обробка аргументів
for arg in "$@"; do
  case $arg in
    domain=*) DOMAIN="${arg#domain=}" ;;
    aliases=*) IFS=',' read -r -a ALIASES <<< "${arg#aliases=}" ;;
    name=*) CERT_NAME="${arg#name=}" ;;
	--reload-nginx) RELOAD_NGINX=true ;;
    *)
      echo "❌ Невідомий аргумент: $arg"
      exit 1
      ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "⚠️  Використання: issue-website-ssl-certificate domain=DOMAIN.COM [aliases=ALIAS1,ALIAS2,...] [name=CERTIFICATE_NAME]"
  exit 1
fi

declare -A DOMAIN_SEEN
declare -a DOMAIN_ARGS

add_domain() {
  local D="$1"
  if [[ -z "${DOMAIN_SEEN[$D]}" ]]; then
    DOMAIN_ARGS+=("-d" "$D")
    DOMAIN_SEEN["$D"]=1
  fi
}

# Додаємо основний домен та його www-версію
ROOT_DOMAIN=$(echo "$DOMAIN" | sed 's/^www\.//')
add_domain "$ROOT_DOMAIN"
add_domain "www.$ROOT_DOMAIN"

# Додаємо aliases (псевдоніми)
for A in "${ALIASES[@]}"; do
  add_domain "$A"
done

# Якщо не вказано CERT_NAME — використовуємо основний домен
if [[ -z "$CERT_NAME" ]]; then
  CERT_NAME="$ROOT_DOMAIN"
fi

# Папка для ACME challenge
WEBROOT="/var/acme_challenge"

if [ ! -d "$WEBROOT" ]; then
  echo "📁 Створюємо директорію $WEBROOT для ACME challenge..."
  sudo mkdir -p "$WEBROOT"
fi

sudo chown www-data:www-data "$WEBROOT"
sudo chmod 755 "$WEBROOT"

# Формуємо команду certbot
CMD=(sudo certbot certonly --webroot --webroot-path "$WEBROOT" --cert-name "$CERT_NAME")

# Додаємо усі домени
for D in "${DOMAIN_ARGS[@]}"; do
  CMD+=("$D")
done

# Вивід
echo "🔐 Certbot команда:"
echo "${CMD[@]}"
echo
echo "📦 Сертифікат буде видано на домени:"
for ((i=1; i<${#DOMAIN_ARGS[@]}; i+=2)); do
  echo "${DOMAIN_ARGS[i]}"
done

read -p "✅ Продовжити? [y/N] " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  "${CMD[@]}"
  STATUS=$?

  if [[ $STATUS -ne 0 ]]; then
    echo "❌ Certbot завершився з помилкою (код $STATUS)"
    exit $STATUS
  fi

  if [ "$RELOAD_NGINX" = true ]; then
    echo "🔁 Перевірка конфігурації NGINX перед перезавантаженням..."
    if sudo nginx -t; then
        echo "✅ Конфігурація валідна. Reload NGINX..."
        sudo systemctl reload nginx
    else
        echo "❌ ПОМИЛКА: Конфігурація nginx некоректна. Перезавантаження скасовано."
        exit 1
    fi
  fi
else
  echo "🚫 Скасовано"
fi
