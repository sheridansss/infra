#!/usr/bin/env bash
# Выгрузка каталога backup/ во внешнее хранилище — защита от гибели сервера.
# Назначение — переменная BACKUP_REMOTE (из окружения или .env):
#   BACKUP_REMOTE=s3:bucket/infra-backup    # rclone-remote (сначала: rclone config)
#   BACKUP_REMOTE=user@host:/backups/infra  # rsync по SSH (ключ без пароля)
#   BACKUP_REMOTE=/mnt/nas/infra            # rsync в примонтированный каталог
# Пустая переменная — выгрузка отключена, скрипт просто выходит.
# Зеркалит backup/ 1-в-1: локальная ротация применяется и к удалённой копии.
# Вызывается автоматически в конце backup.sh; вручную: bash backup-sync.sh
set -euo pipefail

# см. комментарий в backup.sh
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")"

if [ -z "${BACKUP_REMOTE:-}" ] && [ -f .env ]; then
  BACKUP_REMOTE="$(sed -n 's/^BACKUP_REMOTE=//p' .env | tail -n 1 | tr -d '\r')"
fi
if [ -z "${BACKUP_REMOTE:-}" ]; then
  echo "выгрузка наружу не настроена (BACKUP_REMOTE пуст) — пропускаю"
  exit 0
fi

# Отдельный от backup.sh лок: бэкап вызывает выгрузку, не отпуская свой.
if command -v flock >/dev/null 2>&1; then
  exec 9>"${TMPDIR:-/tmp}/infra-backup-sync.lock"
  flock -n 9 || { echo "выгрузка уже выполняется — выхожу"; exit 0; }
fi

# Страховка: пустой локальный каталог не должен затереть удалённую копию.
shopt -s nullglob
COMPLETED=(backup/????-??-??_?????? backup/cold-*)
shopt -u nullglob
if [ "${#COMPLETED[@]}" -eq 0 ]; then
  echo "в backup/ нет ни одного готового бэкапа — выгрузка отменена" >&2
  exit 1
fi

case "$BACKUP_REMOTE" in
  *@*) TOOL=rsync ;;  # user@host:/path — по SSH
  *:*) TOOL=rclone ;; # remote:path — rclone-remote
  *) TOOL=rsync ;;    # локальный путь (NAS и т.п.)
esac
if ! command -v "$TOOL" >/dev/null 2>&1; then
  echo "для BACKUP_REMOTE=$BACKUP_REMOTE нужен $TOOL, а он не установлен" >&2
  exit 1
fi

echo "выгрузка backup/ -> $BACKUP_REMOTE ($TOOL)..."
if [ "$TOOL" = rclone ]; then
  # недописанные каталоги (*.partial) не выгружаем
  rclone sync backup/ "$BACKUP_REMOTE" --exclude '*.partial/**'
else
  rsync -a --delete --exclude '*.partial' backup/ "$BACKUP_REMOTE/"
fi
echo "выгрузка завершена: $BACKUP_REMOTE"
