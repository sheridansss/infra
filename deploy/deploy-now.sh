#!/usr/bin/env bash
# Ручной деплой немедленно: запускается с машины, у которой есть VPN-доступ к серверу.
# Использование: bash deploy/deploy-now.sh user@server [/opt/infra]
set -euo pipefail

SERVER="${1:?использование: deploy-now.sh user@server [путь на сервере]}"
DIR="${2:-/opt/infra}"

# shellcheck disable=SC2029  # подстановка $DIR на стороне клиента — намеренная
ssh "$SERVER" "bash '$DIR/deploy/autodeploy.sh' --force"
