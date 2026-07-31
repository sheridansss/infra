#!/usr/bin/env bash
# Приводит запущенный стек к составу COMPOSE_PROFILES из .env: останавливает
# и удаляет контейнеры выключенных сервисов (данные остаются в volumes),
# поднимает включённые. Запускать после правки COMPOSE_PROFILES:
#   bash deploy/apply-profiles.sh
# Вызывается и из autodeploy.sh — сервер сходится к .env на каждом деплое.
set -euo pipefail

cd "$(dirname "$0")/.."

# Контейнеры сервисов, которые описаны в compose-файле, но выключены в
# COMPOSE_PROFILES. «up --remove-orphans» такие не убирает (для compose они
# не сироты), поэтому останавливаем адресно. Сервисы, удалённые из файла
# совсем, сюда не попадают — их уберёт --remove-orphans ниже.
mapfile -t DISABLED < <(docker compose ps -a --services \
  | grep -xF -f <(docker compose --profile '*' config --services) \
  | grep -vxF -f <(docker compose config --services) || true)

if [ "${#DISABLED[@]}" -gt 0 ]; then
  echo "выключено в COMPOSE_PROFILES: ${DISABLED[*]} — останавливаю"
  docker compose --profile '*' down "${DISABLED[@]}"
fi

docker compose up -d --wait --remove-orphans
