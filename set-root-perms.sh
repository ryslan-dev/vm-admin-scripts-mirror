#!/bin/bash

# Встановлює права і власників для /var та /var/www

echo "🔧 Встановлюємовласника і групу для /var ..."
sudo chown root:root /var

echo "🔧 Встановлюємовласника і групу для /var/www ..."
sudo chown root:root /var/www

echo "🔒 Встановлюємо прав5 для /var ..."
sudo chmod 755 /var

echo "🔒 Встановлюємо права для /var/www ..."
sudo chmod 751 /var/www

echo "✅ Готово: права для /var і /var/www встановлені."
