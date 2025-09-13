# 🔥 GCP VM Backup Creator

Скрипт для створення резервних копій **GCP VM** у вигляді **Snapshots**, **Images** та **Configs**. Зберігає локально, експортує в **Google Cloud Storage (GCS)** та підтримує автоматичне очищення старих бекапів.

---

## 📦 Основні можливості

- 📸 Створення **Snapshots**
- 🖼 Створення **Images**
- 📄 Збереження **конфігурації VM** (JSON)
- ☁️ Експорт бекапів у **GCS Bucket**
- 🧹 Автоочищення старих бекапів локально та в GCS
- 🗑 Автоматичне видалення локальних ресурсів після експорту (**опційно**)

---

## 🚀 Використання

```bash
bash gcp-vm-backup.sh \
  --vm=INSTANCE_NAME \
  --zone=ZONE_NAME \
  --type=snapshot,image,config \
  --export-to-gcs \
  --bucket=BUCKET_NAME \
  --keep-last=3 \
  --cleanup-after-export=snapshot,image \
  --log-file=/var/log/vm-backup.log
```

### 📌 Параметри

| Параметр                 | Опис                                                                    |
| ------------------------ | ----------------------------------------------------------------------- |
| `--vm=INSTANCE_NAME`     | Ім'я VM (за замовчуванням: hostname)                                    |
| `--zone=ZONE_NAME`       | Зона VM (автовизначення, якщо не вказано)                               |
| `--project=PROJECT_ID`   | Проєкт GCP (за замовчуванням: активний проєкт у gcloud)                 |
| `--type=TYPE`            | Типи бекапів: `snapshot`, `image`, `config`, або `all`                  |
| `--export-to-gcs`        | Експортувати у GCS (усі типи)                                           |
| `--export-to-gcs=TYPE`   | Експортувати тільки зазначені типи                                      |
| `--bucket=BUCKET_NAME`   | Ім'я бакету (за замовчуванням: `vm-backups-[PROJECT_ID]`)               |
| `--keep-last=N`          | Скільки останніх бекапів залишати локально та в GCS                     |
| `--storage-class=CLASS`  | Клас зберігання GCS (`ARCHIVE`, `NEARLINE`, `STANDARD`, тощо)           |
| `--cleanup-after-export` | Видаляти локальні ресурси після експорту: `all`, `snapshot,image`, тощо |
| `--log-file=PATH`        | Лог-файл для запису виводу                                              |

---

## 🧹 Автоочищення

- **Локально**: залишає тільки останні `--keep-last` бекапів кожного типу
- **У GCS**: видаляє старі файли, залишаючи останні `--keep-last`
- **Після експорту** (опційно): видаляє локальні Snapshots, Images або Configs

---

## 📖 Приклади

### 1️⃣ Створити всі типи бекапів та експортувати в GCS

```bash
bash gcp-vm-backup.sh --vm=my-instance --zone=europe-west1-b --type=all --export-to-gcs
```

### 2️⃣ Тільки Snapshots + автоочищення після експорту

```bash
bash gcp-vm-backup.sh --type=snapshot --export-to-gcs --cleanup-after-export
```

### 3️⃣ Image та Config без експорту

```bash
bash gcp-vm-backup.sh --type=image,config
```

---

## 📁 Структура локальних бекапів

```
/var/backups/
├── snapshots/
│   └── my-instance-snapshot_YYYY-MM-DD_HH-MM-SS
├── images/
│   └── my-instance-image_YYYY-MM-DD_HH-MM-SS
└── vm-configs/
    └── my-instance-config_YYYY-MM-DD_HH-MM-SS.json
```

---

## ✅ Залежності

- [gcloud CLI](https://cloud.google.com/sdk)
- [gsutil](https://cloud.google.com/storage/docs/gsutil)

---

## ⚠️ Попередження

- Використовуйте з обліковим записом із відповідними правами у GCP.
- Перед використанням переконайтеся, що у вас налаштований `gcloud` та `gsutil`.

---

## 👩‍💻 Автор

> Створено для автоматизації резервного копіювання у GCP.

