#!/usr/bin/env bash
# Доводит .env, созданный до недавних изменений, до актуального набора
# переменных. Вызывается из autodeploy.sh ДО первого docker compose;
# при полном .env ничего не делает. Что дописывает:
#  - COMPOSE_PROFILES: без него активный набор сервисов пуст — up ничего бы
#    не поднял. Дописывается ПРЕЖНИЙ состав (с minio, без seaweedfs), чтобы
#    обновление не меняло набор сервисов уже работающего сервера.
#  - SEAWEEDFS_* и GRAFANA_*: обязательные переменные compose-файла (:?) —
#    без них любой docker compose падает ещё на интерполяции, даже когда
#    сами сервисы выключены в профилях.
set -euo pipefail

cd "$(dirname "$0")/.."

[ -f .env ] || exit 0

if ! grep -q '^COMPOSE_PROFILES=' .env; then
  {
    echo ''
    echo '# Состав стека — см. .env.example (добавлено автоматически при обновлении)'
    echo 'COMPOSE_PROFILES=mongodb,redis,rabbitmq,minio,postgres,pgadmin'
  } >> .env
  echo "в .env добавлен COMPOSE_PROFILES (прежний состав — поведение как раньше)"
fi

if ! grep -q '^SEAWEEDFS_PASSWORD=' .env; then
  {
    echo ''
    echo '# SeaweedFS — см. .env.example (добавлено автоматически при обновлении)'
    echo 'SEAWEEDFS_USER=admin'
    echo "SEAWEEDFS_PASSWORD=$(openssl rand -hex 16)"
  } >> .env
  echo "в .env добавлены SEAWEEDFS_USER и SEAWEEDFS_PASSWORD"
fi

if ! grep -q '^GRAFANA_PASSWORD=' .env; then
  {
    echo ''
    echo '# Grafana — см. .env.example (добавлено автоматически при обновлении)'
    echo 'GRAFANA_USER=admin'
    echo "GRAFANA_PASSWORD=$(openssl rand -hex 16)"
  } >> .env
  echo "в .env добавлены GRAFANA_USER и GRAFANA_PASSWORD"
fi
