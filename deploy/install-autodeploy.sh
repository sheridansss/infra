#!/usr/bin/env bash
# Разовая установка systemd-таймера автодеплоя. Запускать НА СЕРВЕРЕ из каталога репо:
#   bash deploy/install-autodeploy.sh [интервал]
# Интервал по умолчанию — 2min. Нужен sudo-доступ; сам стек работает от текущего
# пользователя (он должен состоять в группе docker).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_USER="${SUDO_USER:-$(whoami)}"
INTERVAL="${1:-2min}"

sudo tee /etc/systemd/system/infra-autodeploy.service > /dev/null <<UNIT
[Unit]
Description=Infra stack pull-deploy
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
User=$RUN_USER
WorkingDirectory=$REPO_DIR
Environment=INFRA_DIR=$REPO_DIR
ExecStart=/usr/bin/bash $REPO_DIR/deploy/autodeploy.sh
UNIT

sudo tee /etc/systemd/system/infra-autodeploy.timer > /dev/null <<UNIT
[Unit]
Description=Periodic infra pull-deploy

[Timer]
OnBootSec=1min
OnUnitActiveSec=$INTERVAL
RandomizedDelaySec=15s

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now infra-autodeploy.timer

echo "Таймер установлен (каждые $INTERVAL). Полезное:"
echo "  systemctl list-timers infra-autodeploy.timer"
echo "  journalctl -u infra-autodeploy.service -f"
