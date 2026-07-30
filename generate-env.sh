#!/usr/bin/env bash
# Создаёт .env из .env.example, заполняя пустые *_PASSWORD значениями openssl rand -hex 16.
# Использование: bash generate-env.sh [--force]
set -euo pipefail

cd "$(dirname "$0")" || exit 1

command -v openssl >/dev/null 2>&1 || { echo "ОШИБКА: openssl не найден в PATH" >&2; exit 1; }

if [[ -f .env && "${1:-}" != "--force" ]]; then
  echo "ОШИБКА: .env уже существует — не перезаписываю." >&2
  echo "Новые пароли сломают доступ к данным, уже созданным в volumes." >&2
  echo "Если уверены: bash generate-env.sh --force" >&2
  exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  if [[ "$line" =~ ^([A-Za-z0-9_]*PASSWORD)=$ ]]; then
    echo "${BASH_REMATCH[1]}=$(openssl rand -hex 16)"
  else
    echo "$line"
  fi
done < .env.example > .env

echo ".env создан. Проверьте BIND_IP и порты перед запуском: docker compose up -d"
