#!/usr/bin/env bash
# Отмена install-backup-timer.sh: выключает и удаляет systemd-таймер ночного бэкапа.
# Запускать НА СЕРВЕРЕ:  bash deploy/uninstall-backup-timer.sh
# Каталог backup/ и уже снятые копии не трогает. Идемпотентен: повторный запуск
# или запуск без установленных юнитов — не ошибка.
set -euo pipefail

command -v systemctl > /dev/null 2>&1 \
  || { echo "systemctl не найден — запускать на сервере (Linux с systemd)" >&2; exit 1; }

# Если прямо сейчас снимается бэкап — дождаться, а не убивать его посреди дампа.
while :; do
  STATE="$(systemctl is-active infra-backup.service 2>/dev/null || true)"
  [ "$STATE" = "activating" ] || [ "$STATE" = "active" ] || break
  echo "бэкап выполняется — жду завершения..."
  sleep 3
done

if [ -f /etc/systemd/system/infra-backup.timer ]; then
  sudo systemctl disable --now infra-backup.timer
fi
sudo rm -f /etc/systemd/system/infra-backup.timer /etc/systemd/system/infra-backup.service
sudo systemctl daemon-reload
sudo systemctl reset-failed infra-backup.service 2> /dev/null || true

echo "Таймер бэкапа выключен и удалён; каталог backup/ не тронут."
echo "Установить обратно: bash deploy/install-backup-timer.sh"
