#!/usr/bin/env bash
# Восстановление сервисов из онлайн-бэкапа, созданного backup.sh.
#   bash restore.sh <backup/<дата> | latest> [--yes] [сервис...]
# Примеры:
#   bash restore.sh latest                          # весь стек из свежайшей копии
#   bash restore.sh backup/2026-07-30_232627 redis  # один сервис из конкретной
# Что делает по сервисам:
#   mongodb  — mongorestore --drop --oplogReplay (коллекции заменяются)
#   postgres — пересоздаёт кластер (volume) и заливает pg_dumpall
#   redis    — подкладывает RDB-снапшот через одноразовый сервер без AOF
#   rabbitmq — rabbitmqctl import_definitions поверх текущих
#   minio    — mc mirror --overwrite поверх текущих
# Холодные бэкапы (backup/cold-*) восстанавливаются иначе — см. README.
set -euo pipefail

# см. комментарий в backup.sh
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")"

ALL_SERVICES=(mongodb postgres redis rabbitmq minio)

# Включённые сервисы: состав стека задаёт COMPOSE_PROFILES в .env.
ENABLED_LIST="$(docker compose config --services)"
ENABLED=()
for SVC in "${ALL_SERVICES[@]}"; do
  if grep -qx "$SVC" <<< "$ENABLED_LIST"; then
    ENABLED+=("$SVC")
  fi
done

usage() {
  echo "использование: restore.sh <backup/<дата> | latest> [--yes] [сервис...]" >&2
  echo "сервисы: ${ALL_SERVICES[*]} (без указания — все включённые в COMPOSE_PROFILES)" >&2
  exit 1
}

[ $# -ge 1 ] || usage
SRC="$1"
shift

YES=0
SERVICES=()
for ARG in "$@"; do
  case "$ARG" in
    --yes) YES=1 ;;
    mongodb | postgres | redis | rabbitmq | minio) SERVICES+=("$ARG") ;;
    *)
      echo "неизвестный аргумент: $ARG" >&2
      usage
      ;;
  esac
done
[ "${#SERVICES[@]}" -gt 0 ] || SERVICES=("${ENABLED[@]}")
if [ "${#SERVICES[@]}" -eq 0 ]; then
  echo "в COMPOSE_PROFILES нет ни одного сервиса с данными — нечего восстанавливать" >&2
  exit 1
fi

# Явно названный, но выключенный сервис — ошибка до каких-либо действий.
for SVC in "${SERVICES[@]}"; do
  if ! grep -qx "$SVC" <<< "$ENABLED_LIST"; then
    echo "сервис $SVC отключён в COMPOSE_PROFILES (.env) — включите его и выполните docker compose up -d" >&2
    exit 1
  fi
done

if [ "$SRC" = "latest" ]; then
  shopt -s nullglob
  DIRS=(backup/????-??-??_??????)
  shopt -u nullglob
  if [ "${#DIRS[@]}" -eq 0 ]; then
    echo "в backup/ нет ни одного онлайн-бэкапа" >&2
    exit 1
  fi
  SRC="${DIRS[${#DIRS[@]} - 1]}"
fi
[ -d "$SRC" ] || { echo "каталог $SRC не найден" >&2; exit 1; }

# Комплектность каталога — до первого разрушающего действия.
declare -A FILE=(
  [mongodb]=mongodb.archive.gz
  [postgres]=postgres.sql.gz
  [redis]=redis.rdb
  [rabbitmq]=rabbitmq-definitions.json
  [minio]=minio.tar.gz
)
for SVC in "${SERVICES[@]}"; do
  if [ ! -s "$SRC/${FILE[$SVC]}" ]; then
    echo "в $SRC нет файла ${FILE[$SVC]} — каталог неполон, восстановление отменено" >&2
    exit 1
  fi
done

# Стек должен работать (postgres пересоздаётся, но должен существовать в конфиге).
for SVC in "${SERVICES[@]}"; do
  if [ -z "$(docker compose ps --status running -q "$SVC")" ]; then
    echo "сервис $SVC не запущен — сначала docker compose up -d" >&2
    exit 1
  fi
done

echo "Восстановление из $SRC (created: $(sed -n 's/^created: *//p' "$SRC/manifest.txt" 2>/dev/null || echo '?'))"
echo "Текущие данные будут заменены: ${SERVICES[*]}"
if [ "$YES" != 1 ]; then
  if [ ! -t 0 ]; then
    echo "неинтерактивный запуск: подтвердите флагом --yes" >&2
    exit 1
  fi
  read -r -p "Продолжить? [y/N] " ANSWER
  case "$ANSWER" in
    y | Y | yes | да) ;;
    *)
      echo "отменено"
      exit 0
      ;;
  esac
fi

restore_mongodb() {
  echo "--- mongodb: mongorestore --drop --oplogReplay..."
  docker compose exec -T mongodb sh -c \
    'mongorestore -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
       --authenticationDatabase admin --archive --gzip --drop --oplogReplay' \
    < "$SRC/mongodb.archive.gz"
}

restore_postgres() {
  echo "--- postgres: пересоздание кластера из pg_dumpall..."
  docker compose rm -sf postgres
  if docker volume inspect services_pg_data > /dev/null 2>&1; then
    docker volume rm services_pg_data
  fi
  docker compose up -d --wait postgres
  echo "    (сообщение 'role \"postgres\" already exists' ниже — норма)"
  gunzip -c "$SRC/postgres.sql.gz" | docker compose exec -T postgres \
    sh -c 'psql -q -U "$POSTGRES_USER" -d postgres'
}

restore_redis() {
  echo "--- redis: загрузка RDB-снапшота..."
  docker compose stop redis
  docker run --rm -i -v services_redis_data:/data alpine:3 \
    sh -c 'rm -rf /data/appendonlydir && cat > /data/dump.rdb' < "$SRC/redis.rdb"
  # При включённом AOF Redis игнорирует dump.rdb (даже когда AOF-файлов нет),
  # поэтому грузим снапшот одноразовым сервером без AOF и включаем AOF
  # уже на загруженных данных. Образ держим тем же, что в docker-compose.yml.
  docker rm -f infra-redis-restore > /dev/null 2>&1 || true
  docker run --rm -d --name infra-redis-restore -v services_redis_data:/data \
    redis:8-alpine redis-server --appendonly no > /dev/null
  docker exec infra-redis-restore sh -c '
    until redis-cli ping 2>/dev/null | grep -q PONG; do sleep 1; done
    redis-cli config set appendonly yes > /dev/null
    while redis-cli info persistence | grep -Eq "aof_rewrite_in_progress:1|aof_rewrite_scheduled:1"; do sleep 1; done
    echo "    загружено ключей: $(redis-cli dbsize)"'
  docker stop infra-redis-restore > /dev/null
  docker compose start redis
}

restore_rabbitmq() {
  echo "--- rabbitmq: import_definitions..."
  docker compose cp "$SRC/rabbitmq-definitions.json" rabbitmq:/tmp/defs.json
  docker compose exec -T rabbitmq sh -c 'rabbitmqctl import_definitions /tmp/defs.json && rm /tmp/defs.json'
}

restore_minio() {
  echo "--- minio: mc mirror --overwrite..."
  local TMP="$SRC/minio-restore.tmp"
  rm -rf "$TMP" && mkdir -p "$TMP"
  tar -xzf "$SRC/minio.tar.gz" -C "$TMP"
  if [ -z "$(find "$TMP" -mindepth 1 -print -quit)" ]; then
    echo "    в бэкапе нет бакетов — нечего восстанавливать"
    rm -rf "$TMP"
    return 0
  fi
  docker compose cp "$TMP" minio:/tmp/minio-restore
  rm -rf "$TMP"
  docker compose exec -T minio sh -c \
    'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" > /dev/null \
       && mc mirror --overwrite /tmp/minio-restore local/ && rm -rf /tmp/minio-restore'
}

for SVC in "${SERVICES[@]}"; do
  "restore_$SVC"
done

echo "восстановление из $SRC завершено: ${SERVICES[*]}"
