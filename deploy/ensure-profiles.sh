#!/usr/bin/env bash
# Дописывает в .env полный COMPOSE_PROFILES, если переменной там нет.
# Нужен при обновлении сервера: .env, созданный до появления профилей, даёт
# пустой активный набор — docker compose up не поднял бы ничего, а
# --remove-orphans снёс бы работающие контейнеры. Вызывается из autodeploy.sh
# ДО первого docker compose; при уже заданной переменной ничего не делает.
set -euo pipefail

cd "$(dirname "$0")/.."

[ -f .env ] || exit 0
if ! grep -q '^COMPOSE_PROFILES=' .env; then
  {
    echo ''
    echo '# Состав стека — см. .env.example (добавлено автоматически при обновлении)'
    echo 'COMPOSE_PROFILES=mongodb,redis,rabbitmq,minio,postgres,pgadmin'
  } >> .env
  echo "в .env добавлен COMPOSE_PROFILES (полный набор — поведение как раньше)"
fi
