#!/bin/bash

# Вхідні параметри
ACCOUNT="${1:-}"
DOMAIN="${2:-}"

if [[ -z "$DOMAIN" || -z "$ACCOUNT" ]]; then
  echo "❌ Вкажіть обов'язкові параметри: domain account"
  exit 1
fi

# Перевірка чи існує системний користувач акаунта
if ! id "$ACCOUNT" &>/dev/null; then
  echo "❌ Користувач акаунта $ACCOUNT не існує."
  exit 2
fi

BASE_DIR="/var/www/$ACCOUNT/data/www"
DOMAIN_DIR="$BASE_DIR/$DOMAIN"

# Перевірка чи існує папка з доменом
if [[ -d "$DOMAIN_DIR" ]]; then
  echo "❌ Папка для домену $DOMAIN вже існує."
  exit 3
fi

# Якщо базова папка акаунта не існує — створюємо та виставляємо права
if [[ ! -d "$BASE_DIR" ]]; then
  echo "ℹ️ Створюємо базову папку $BASE_DIR"
  sudo mkdir -p "$BASE_DIR"
  echo "ℹ️ Виконуємо sudo set-webaccount-perms $ACCOUNT"
  sudo set-webaccount-perms "$ACCOUNT"
fi

# Створюємо папку домену
echo "ℹ️ Створюємо папку для сайту $DOMAIN_DIR"
sudo mkdir -p "$DOMAIN_DIR"

# Створюємо файл index.php з вмістом парковки
sudo tee "$DOMAIN_DIR/index.html" > /dev/null <<'EOF'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">

<html>
<body bgcolor="#FFFFFF">
<table border=0 width=100% height=100%>
<tr>
  <td align=center><table border=0 cellpadding=0 cellspacing=0 width=300>
  <tr><td bgcolor=#000000><table border=0 cellpadding=3 cellspacing=1 width=300>
  <tr>
    <td align=center bgcolor=#0000FF><font color=#FFFFFF face='Verdana, Arial, Helvetica, sans-serif' size=2><b>Welcome !</b></font></td>
  </tr>
  <tr>
    <td align=center bgcolor=#FFFFFF><font color=#000000 face='Verdana, Arial, Helvetica, sans-serif' size=2><b>Site just created.<br><br>Real content coming soon.</b></font></td>
  </tr>
  </table></td></tr></table>
  </td>
</tr>
</table>
</body>
</html>
EOF

# Встановлюємо права для папки домену та файлу (за допомогою sudo set-webaccount-perms)
echo "ℹ️ Встановлюємо права власника та групи через sudo set-webaccount-perms $ACCOUNT"
sudo set-webaccount-perms "$ACCOUNT"

echo "✅ Сайт $DOMAIN для акаунта $ACCOUNT створено успішно."
