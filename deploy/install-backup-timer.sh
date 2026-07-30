#!/usr/bin/env bash
# Разовая установка systemd-таймера ночного бэкапа (backup.sh). Запускать НА СЕРВЕРЕ:
#   bash deploy/install-backup-timer.sh ["*-*-* 03:30:00"]
# Аргумент — расписание в формате systemd OnCalendar; по умолчанию ежедневно в 03:30.
# Нужен sudo-доступ; сам бэкап работает от текущего пользователя (группа docker).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_USER="${SUDO_USER:-$(whoami)}"
SCHEDULE="${1:-*-*-* 03:30:00}"

sudo tee /etc/systemd/system/infra-backup.service > /dev/null <<UNIT
[Unit]
Description=Infra stack online backup
After=docker.service

[Service]
Type=oneshot
User=$RUN_USER
WorkingDirectory=$REPO_DIR
Environment=BACKUP_KEEP=7
ExecStart=/usr/bin/bash $REPO_DIR/backup.sh
UNIT

sudo tee /etc/systemd/system/infra-backup.timer > /dev/null <<UNIT
[Unit]
Description=Nightly infra backup

[Timer]
OnCalendar=$SCHEDULE
RandomizedDelaySec=5min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now infra-backup.timer

echo "Таймер бэкапа установлен ($SCHEDULE). Полезное:"
echo "  systemctl list-timers infra-backup.timer"
echo "  journalctl -u infra-backup.service -f"
echo "  число хранимых копий: Environment=BACKUP_KEEP в infra-backup.service"
