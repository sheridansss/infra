#!/usr/bin/env bash
# Холодный бэкап: останавливает стек и архивирует ВСЕ volumes как есть (1-в-1),
# включая настройки pgAdmin, IAM-пользователей MinIO и служебное состояние replica set.
# Ниша — переезд на другой сервер и точка отката перед мажорным обновлением;
# для регулярных бэкапов есть backup.sh (без даунтайма).
# Использование:  bash backup-cold.sh [--yes]
set -euo pipefail

# см. комментарий в backup.sh
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")"

if [ "${1:-}" != "--yes" ]; then
  if [ ! -t 0 ]; then
    echo "неинтерактивный запуск: подтвердите даунтайм флагом --yes" >&2
    exit 1
  fi
  read -r -p "Стек будет остановлен на время архивации. Продолжить? [y/N] " ANSWER
  case "$ANSWER" in
    y | Y | yes | да) ;;
    *)
      echo "отменено"
      exit 0
      ;;
  esac
fi

mapfile -t VOLUMES < <(docker volume ls -q --filter label=com.docker.compose.project=services | sort)
if [ "${#VOLUMES[@]}" -eq 0 ]; then
  echo "volumes проекта services не найдены — стек ещё не поднимался?" >&2
  exit 1
fi

STAMP="$(date +%F_%H%M%S)"
DEST="backup/cold-$STAMP"
mkdir -p "$DEST"

# Если архивация сорвётся на середине — стек всё равно поднимем обратно.
STACK_DOWN=0
cleanup() {
  if [ "$STACK_DOWN" = 1 ]; then
    echo "ошибка — поднимаю стек обратно..." >&2
    docker compose up -d --wait || true
  fi
}
trap cleanup EXIT

echo "останавливаю стек..."
docker compose down
STACK_DOWN=1

for VOL in "${VOLUMES[@]}"; do
  echo "архивирую $VOL..."
  docker run --rm -v "$VOL:/source:ro" alpine:3 tar -czf - -C /source . > "$DEST/$VOL.tgz"
done

echo "поднимаю стек..."
docker compose up -d --wait
STACK_DOWN=0

echo "готово: $DEST"
du -h "$DEST"/* | sed 's/^/  /'
