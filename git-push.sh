#!/usr/bin/env bash
set -euo pipefail

# defaults
REPO="."
MSG="Автооновлення"

# parse named args
while (( "$#" )); do
  case "$1" in
    --repo|--dir|-r|-d)
      REPO="${2:-}"; shift 2 ;;
    --repo=*|--dir=*|-r=*|-d=*)
      REPO="${1#*=}"; shift ;;
    --msg|-m)
      MSG="${2:-}"; shift 2 ;;
    --msg=*-m=*)
      MSG="${1#*=}"; shift ;;
    -h|--help)
      cat <<'USAGE'
git-push [--repo <path>] [--msg "<message>"]

  --repo, -r   Шлях до git-папки (де .git). За замовчуванням: поточна.
  --msg,  -m   Повідомлення коміту. За замовчуванням: "Автооновлення".
USAGE
      exit 0 ;;
    *)
      echo "Невідомий аргумент: $1" >&2; exit 1 ;;
  esac
done

# remember cwd and ensure we return
CWD="$(pwd)"
cleanup(){ cd "$CWD" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# go to repo
cd "$REPO"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌  Не git-репозиторій: $(pwd)" >&2
  exit 1
fi

# stage all
git add -A

# commit only if staged changes exist
if ! git diff --cached --quiet --ignore-submodules --; then
  git commit -m "$MSG"
else
  echo "ℹ️  Немає змін для коміту — пропускаю commit"
fi

# push (set upstream if missing)
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git push
else
  branch="$(git rev-parse --abbrev-ref HEAD)"
  echo "ℹ️  Upstream не налаштований. Встановлюю: origin/$branch"
  git push -u origin "$branch"
fi

echo "✅  Готово"
