# 🔥 VM Admin scripts

Пакет скриптів для роботи в SHELL на віртуальній машині VM

---

## 📁 Структура

```
/vm-admin-scripts/
├── bin/
│   └── виконувані скрипти
└── lib/
    └── бібліотеки
```

## 📦 Список скриптів

Виконувані файли в папці /bin/

---

  ### 📦 Бекапи
  backup-admin-scripts.sh
  backup-website.sh
  backup-website-db.sh
  backup-website-files.sh

  ### 🌀 WordPress
  clone-wordpress.sh
  install-wordpress.sh
  delete-wordpress.sh
  
  ### 🌐 Веб-панель
  init-webpanel.sh
  create-webaccount.sh
  delete-webaccount.sh
  create-website.sh

  ### 📂 FTP
  add-ftpuser.sh
  get-ftpuser.sh
  update-ftpuser.sh
  delete-ftpuser.sh

  ### 🛠️ Права
  set-webaccount-perms.sh
  set-root-perms.sh
  
  ### SSL
  issue-website-ssl-certificate.sh
  renew-ssl-certificates.sh

  ### 🌍 GCP
  gcp-backup-disk.sh
  gcp-backup-folder-map.sh
  gcp-backup-manager.sh
  gcp-create-disk.sh
  gcp-create-instance.sh
  gcp-create-template-from-config.sh
  gcp-disk-backup-list.sh
  gcp-disk-is-attached.sh
  gcp-find-disk.sh
  gcp-resize-disk-fs.sh
  gcp-restore-config.sh
  gcp-restore-disk.sh
  gcp-set-disk-auto-delete.sh

  ### ⚙️ Components manager
  components-manager.sh
  
  ### 👥️ Користувачі
  get-sudo-users.sh
  get-sudo-groups.sh
  add-user.sh
  add-webuser.sh
  delete-user.sh
  delete-group.sh
  lock-user.sh
  unlock-user.sh
  change-user-shell.sh
  change-user-dir.sh
  add-user-to-group.sh
  delete-user-from-group.sh
  check-oslogin.sh
  
  ### Провідник
  shell-explorer.sh
  shell-explorers.sh
  setup-tmux.sh
  
  ### ⚙️ Інші утиліти
  menu-choose.sh
  import-db-table.sh
  kill-user-vscode-processes.sh
  restart-php-pool.sh
  set-wp-language.sh
  upload-as-root.sh
  vsedit.sh
  
## 🧮 Бібліотеки

Файли бібліотек в папці /lib/

---

  ### /lib/components-manager/
  components-data.sh
  component-package.sh
  component-service.sh
  component-user.sh
  component-webuser.sh
  component-ftpuser.sh
  component-database.sh
  component-system.sh
  component-explorer.sh

  ### /lib/menu-choose/
  menu-choose.sh
