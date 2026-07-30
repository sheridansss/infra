#!/usr/bin/env bash
# Онлайн-бэкап штатными инструментами БД — на работающем стеке, без даунтайма:
# mongodump --oplog, pg_dumpall, RDB-снапшот Redis, definitions RabbitMQ, зеркало MinIO.
# Использование:  bash backup.sh
# Результат: backup/<дата_время>/; хранятся последние BACKUP_KEEP копий (по умолчанию 7).
# Запускается вручную или systemd-таймером (deploy/install-backup-timer.sh).
# Настройки pgAdmin и IAM-пользователи MinIO сюда не входят — их покрывает backup-cold.sh.
set -euo pipefail

# Git Bash на Windows переписывает аргументы вида x:/y и /tmp/... в windows-пути —
# отключаем; на Linux переменная ни на что не влияет.
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")"
KEEP="${BACKUP_KEEP:-7}"

# Защита от параллельных запусков (таймер + ручной). В Git Bash flock нет — там без лока.
if command -v flock >/dev/null 2>&1; then
  exec 9>"${TMPDIR:-/tmp}/infra-backup.lock"
  flock -n 9 || { echo "бэкап уже выполняется — выхожу"; exit 0; }
fi

for SVC in mongodb postgres redis rabbitmq minio; do
  if [ -z "$(docker compose ps --status running -q "$SVC")" ]; then
    echo "сервис $SVC не запущен — бэкап отменён (нужен docker compose up -d)" >&2
    exit 1
  fi
done

STAMP="$(date +%F_%H%M%S)"
# Пишем во временный каталог; финальное имя он получает только при полном успехе,
# так что ротация и restore никогда не увидят недописанный бэкап.
DEST="backup/$STAMP.partial"
rm -rf backup/*.partial
mkdir -p "$DEST"

echo "mongodb: mongodump --oplog..."
docker compose exec -T mongodb sh -c \
  'mongodump -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin --oplog --archive --gzip --quiet' \
  > "$DEST/mongodb.archive.gz"

echo "postgres: pg_dumpall..."
docker compose exec -T postgres sh -c 'pg_dumpall -U "$POSTGRES_USER"' | gzip > "$DEST/postgres.sql.gz"

echo "redis: BGSAVE..."
docker compose exec -T redis sh -c '
  prev=$(redis-cli LASTSAVE)
  redis-cli BGSAVE > /dev/null
  for i in $(seq 1 60); do
    [ "$(redis-cli LASTSAVE)" != "$prev" ] && exit 0
    sleep 1
  done
  echo "BGSAVE не завершился за 60 секунд" >&2
  exit 1
'
docker compose cp redis:/data/dump.rdb "$DEST/redis.rdb"

echo "rabbitmq: export_definitions..."
docker compose exec -T rabbitmq rabbitmqctl export_definitions - > "$DEST/rabbitmq-definitions.json"

echo "minio: mc mirror..."
# tar внутри образа MinIO нет, поэтому зеркалим в /tmp контейнера,
# забираем каталог через compose cp и архивируем уже на хосте.
docker compose exec -T minio sh -c '
  mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" > /dev/null
  rm -rf /tmp/minio-mirror && mkdir -p /tmp/minio-mirror
  if [ -n "$(mc ls local/)" ]; then
    mc mirror --quiet local/ /tmp/minio-mirror > /dev/null
  fi
'
docker compose cp minio:/tmp/minio-mirror "$DEST/minio-mirror"
docker compose exec -T minio rm -rf /tmp/minio-mirror
tar -czf "$DEST/minio.tar.gz" -C "$DEST/minio-mirror" .
rm -rf "$DEST/minio-mirror"

{
  echo "created: $(date '+%F %T %Z')"
  echo "host:    $(hostname)"
  echo "commit:  $(git rev-parse --short HEAD 2>/dev/null || echo '-')"
} > "$DEST/manifest.txt"

mv "$DEST" "backup/$STAMP"

# Ротация: оставляем KEEP последних (холодные бэкапы cold-* не трогаем).
shopt -s nullglob
ALL=(backup/????-??-??_??????)
shopt -u nullglob
if [ "${#ALL[@]}" -gt "$KEEP" ]; then
  for OLD in "${ALL[@]:0:$(( ${#ALL[@]} - KEEP ))}"; do
    echo "ротация: удаляю $OLD"
    rm -rf "$OLD"
  done
fi

echo "готово: backup/$STAMP"
du -h "backup/$STAMP"/* | sed 's/^/  /'
