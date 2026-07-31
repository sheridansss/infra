#!/usr/bin/env bash
# Pull-деплой: подтягивает origin/main и перезапускает стек, если есть изменения.
# Запускается systemd-таймером (см. install-autodeploy.sh) или вручную:
#   bash deploy/autodeploy.sh [--force]
# --force — применить, даже если новых коммитов нет (например, после ручного down).
set -euo pipefail

REPO_DIR="${INFRA_DIR:-/opt/infra}"

# Защита от параллельных запусков. На сервере flock есть всегда;
# в Git Bash на Windows его нет — там работаем без лока.
if command -v flock >/dev/null 2>&1; then
  exec 9>"${TMPDIR:-/tmp}/infra-autodeploy.lock"
  flock -n 9 || { echo "автодеплой уже выполняется — выхожу"; exit 0; }
fi

cd "$REPO_DIR"

git fetch --quiet origin main
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ] && [ "${1:-}" != "--force" ]; then
  echo "изменений нет (HEAD=$(git rev-parse --short HEAD))"
  exit 0
fi

echo "обновление: $(git rev-parse --short HEAD) -> $(git rev-parse --short origin/main)"
# reset --hard, а не merge: рабочая копия на сервере — зеркало origin/main.
# Неотслеживаемые файлы (.env, backup/) reset не трогает; git clean НЕ используем,
# чтобы случайно их не удалить.
git reset --hard --quiet origin/main

if [ ! -f .env ]; then
  echo "первый деплой: генерирую .env"
  bash generate-env.sh
fi
# .env со времён до профилей не знает COMPOSE_PROFILES — дописать до первого
# docker compose, иначе активный набор сервисов окажется пустым
bash deploy/ensure-profiles.sh

docker compose pull --quiet
# apply-profiles: поднимает включённые в COMPOSE_PROFILES сервисы, а контейнеры
# выключенных (или убранных из compose-файла) останавливает и удаляет —
# данные остаются в volumes
bash deploy/apply-profiles.sh
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
echo "готово: $(git rev-parse --short HEAD)"
