# PostgreSQL с исправлением Brotli

Временная сборка основана на официальном `postgres:18.6-alpine3.24`, закреплённом по digest в Dockerfile. Один слой обновляет `brotli-libs` с `1.2.0-r1` до `1.2.1-r0`, исправляя [CVE-2026-111497](https://security.alpinelinux.org/vuln/CVE-2026-111497). При сравнении пакетов с базовым образом меняется только Brotli; версия PostgreSQL, ICU и musl совпадает с базой.

Готовая сборка для `linux/amd64` публикуется в `ghcr.io/sheridansss/postgres`, а Compose использует её точный digest. Штатный entrypoint подготавливает права на том и запускает PostgreSQL через `gosu` от пользователя `postgres` (UID 70). Healthcheck задаётся в Compose; это объясняет локальное исключение KICS у строки `FROM`.

Проверить сборку из корня репозитория:

```bash
docker build --platform linux/amd64 --tag infra-postgres:verify images/postgres
docker run --rm --network none --entrypoint postgres infra-postgres:verify --version
```

Для следующей публикации нужен новый тег в GHCR и новый digest в Compose. Перед переключением проверяются CVE, запуск PostgreSQL и полный CI с циклом backup/restore.

## Возврат на официальный образ

1. Dependabot предложит обновление версии или digest официальной базы в Dockerfile. CI пересоберёт рецепт и проверит его CVE.
2. Когда официальный образ той же ветки `postgres:18-alpine3.24` уже содержит `brotli-libs >= 1.2.1-r0`, проверить его полным CVE-сканом по политике репозитория и прогнать smoke, backup/restore и профили с этим образом.
3. Переключить Compose на официальный тег с проверенным digest. Удалить временный Dockerfile, его отдельную сборку в CI и запись Dependabot для `/images/postgres`.
4. Сохранить опубликованную сборку в GHCR как фиксированную точку отката. Она не участвует в новых деплоях после переключения Compose.
