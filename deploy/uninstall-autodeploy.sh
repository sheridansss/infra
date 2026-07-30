#!/usr/bin/env bash
# Отмена install-autodeploy.sh: выключает и удаляет systemd-таймер автодеплоя.
# Запускать НА СЕРВЕРЕ:  bash deploy/uninstall-autodeploy.sh
# Репозиторий, .env и данные стека не трогает. Идемпотентен: повторный запуск
# или запуск без установленных юнитов — не ошибка.
set -euo pipefail

command -v systemctl > /dev/null 2>&1 \
  || { echo "systemctl не найден — запускать на сервере (Linux с systemd)" >&2; exit 1; }

# Если прямо сейчас идёт деплой — дождаться, а не убивать его посреди git reset.
while :; do
  STATE="$(systemctl is-active infra-autodeploy.service 2>/dev/null || true)"
  [ "$STATE" = "activating" ] || [ "$STATE" = "active" ] || break
  echo "деплой выполняется — жду завершения..."
  sleep 3
done

if [ -f /etc/systemd/system/infra-autodeploy.timer ]; then
  sudo systemctl disable --now infra-autodeploy.timer
fi
sudo rm -f /etc/systemd/system/infra-autodeploy.timer /etc/systemd/system/infra-autodeploy.service
sudo systemctl daemon-reload
sudo systemctl reset-failed infra-autodeploy.service 2> /dev/null || true

echo "Автодеплой выключен и удалён; репозиторий и стек не тронуты."
echo "Установить обратно: bash deploy/install-autodeploy.sh"
