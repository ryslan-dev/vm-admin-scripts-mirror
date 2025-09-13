#!/bin/bash

# 💥 Налаштування вартості за ГБ/міс
SNAPSHOT_COST_GB=0.026   # $0.026/GB/місяць
IMAGE_COST_GB=0.05       # $0.05/GB/місяць

# 🔥 Налаштування дефолтів
KEEP_LAST=5              # Скільки останніх бекапів залишати при cleanup
BUCKET="vm-backups-$(gcloud config get-value project 2>/dev/null)" # Назва бакету для експорту
STORAGE_CLASS="ARCHIVE" # STORAGE_CLASS: STANDARD | NEARLINE | COLDLINE | ARCHIVE

# 💬 Функція для виводу заголовків
header() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔹 $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 🏁 Перевірка аргументів
DO_CLEANUP=false
DO_EXPORT=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cleanup) DO_CLEANUP=true ;;
        --export-to-gcs) DO_EXPORT=true ;;
        --keep-last=*) KEEP_LAST="${1#*=}" ;;
        --bucket=*) BUCKET="${1#*=}" ;;
        --storage-class=*) STORAGE_CLASS="${1#*=}" ;;
        *) echo "❌ Невідомий параметр: $1" && exit 1 ;;
    esac
    shift
done

# 🌍 Отримуємо список усіх проектів
PROJECTS=$(gcloud projects list --format="value(projectId)" 2>/dev/null)

if [ -z "$PROJECTS" ]; then
    echo "⚠️ Не знайдено жодного проекту. Перевір gcloud auth."
    exit 1
fi

TOTAL_GB=0
TOTAL_COST=0

for PROJECT in $PROJECTS; do
    header "Проект: $PROJECT"
    gcloud config set project $PROJECT >/dev/null

    # 📸 SNAPSHOTS
    echo "📸 Snapshot-и:"
    gcloud compute snapshots list \
      --format="table(name, diskSizeGb, creationTimestamp, storageLocations)" \
      | tee /tmp/${PROJECT}_snapshots.txt

    SNAPSHOT_TOTAL_GB=$(awk 'NR>1 {sum+=$2} END {print sum}' /tmp/${PROJECT}_snapshots.txt)
    SNAPSHOT_TOTAL_GB=${SNAPSHOT_TOTAL_GB:-0}
    SNAPSHOT_TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $SNAPSHOT_TOTAL_GB * $SNAPSHOT_COST_GB}")

    echo "📦 Snapshot-и: ${SNAPSHOT_TOTAL_GB} GB"
    echo "💲 Snapshot-и: \$${SNAPSHOT_TOTAL_COST}/місяць"
    echo ""

    # 🖼 IMAGES
    echo "🖼 Image-и:"
    gcloud compute images list \
      --no-standard-images \
      --format="table(name, diskSizeGb, creationTimestamp, storageLocations)" \
      | tee /tmp/${PROJECT}_images.txt

    IMAGE_TOTAL_GB=$(awk 'NR>1 {sum+=$2} END {print sum}' /tmp/${PROJECT}_images.txt)
    IMAGE_TOTAL_GB=${IMAGE_TOTAL_GB:-0}
    IMAGE_TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $IMAGE_TOTAL_GB * $IMAGE_COST_GB}")

    echo "📦 Image-и: ${IMAGE_TOTAL_GB} GB"
    echo "💲 Image-и: \$${IMAGE_TOTAL_COST}/місяць"
    echo ""

    # 📊 Сумуємо
    TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_GB + $SNAPSHOT_TOTAL_GB + $IMAGE_TOTAL_GB}")
    TOTAL_COST=$(awk "BEGIN {printf \"%.2f\", $TOTAL_COST + $SNAPSHOT_TOTAL_COST + $IMAGE_TOTAL_COST}")

    # 🚮 Чищення старих бекапів
    if $DO_CLEANUP; then
        echo "🧹 Видалення старих Snapshots (залишаємо $KEEP_LAST):"
        SNAPSHOTS_TO_DELETE=$(gcloud compute snapshots list \
          --sort-by=~creationTimestamp \
          --format="value(name)" \
          | tail -n +$(($KEEP_LAST + 1)))
        for SNAP in $SNAPSHOTS_TO_DELETE; do
            echo "🗑 Видаляю snapshot: $SNAP"
            gcloud compute snapshots delete $SNAP --quiet
        done

        echo "🧹 Видалення старих Images (залишаємо $KEEP_LAST):"
        IMAGES_TO_DELETE=$(gcloud compute images list \
          --no-standard-images \
          --sort-by=~creationTimestamp \
          --format="value(name)" \
          | tail -n +$(($KEEP_LAST + 1)))
        for IMG in $IMAGES_TO_DELETE; do
            echo "🗑 Видаляю image: $IMG"
            gcloud compute images delete $IMG --quiet
        done
    fi

    # 📥 Експорт у GCS
    if $DO_EXPORT; then
        echo "📤 Експорт Snapshots та Images у бакет gs://${BUCKET} (клас: $STORAGE_CLASS)"
        # Створюємо бакет якщо немає
        gsutil mb -c $STORAGE_CLASS -l us gs://$BUCKET 2>/dev/null || true

        for SNAP in $(awk 'NR>1 {print $1}' /tmp/${PROJECT}_snapshots.txt); do
            echo "⬆️ Експорт snapshot: $SNAP"
            gcloud compute snapshots export $SNAP \
              --destination-uri="gs://$BUCKET/snapshots/${SNAP}.tar.gz" \
              --quiet || echo "⚠️ Пропущено (можливо не підтримується)"
        done

        for IMG in $(awk 'NR>1 {print $1}' /tmp/${PROJECT}_images.txt); do
            echo "⬆️ Експорт image: $IMG"
            gcloud compute images export $IMG \
              --destination-uri="gs://$BUCKET/images/${IMG}.tar.gz" \
              --quiet || echo "⚠️ Пропущено (можливо не підтримується)"
        done
    fi

done

header "✅ Сумарно у всіх проектах"
echo "📦 ${TOTAL_GB} GB"
echo "💰 \$${TOTAL_COST}/місяць"
