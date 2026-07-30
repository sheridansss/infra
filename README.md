# Инфраструктурный стек

Один compose-файл поднимает: **MongoDB 8.0**, **Redis 8**, **RabbitMQ 4** (с management-UI), **MinIO** (S3-хранилище), **PostgreSQL 18** и **pgAdmin 4**. Все пароли и порты — в `.env`.

## Запуск

```bash
bash generate-env.sh      # Linux/macOS: создаёт .env со сгенерированными паролями
# .\generate-env.ps1      # то же самое на Windows (PowerShell)
docker compose up -d
docker compose ps         # дождаться статуса healthy у всех сервисов
```

Скрипт не перезаписывает существующий `.env` (чтобы не оторвать пароли от уже созданных данных) — для пересоздания добавьте `--force` / `-Force`.

`.env` не коммитится в git (см. `.gitignore`).

## Порты и строки подключения

| Сервис        | Порт  | Подключение                                  |
| ------------- | ----- | -------------------------------------------- |
| MongoDB       | 27017 | `mongodb://root:<пароль>@<host>:27017/?authSource=admin&directConnection=true` |
| Redis         | 6379  | `redis://:<пароль>@<host>:6379/0`            |
| RabbitMQ AMQP | 5672  | `amqp://admin:<пароль>@<host>:5672/`         |
| RabbitMQ UI   | 15672 | `http://<host>:15672`                        |
| MinIO S3 API  | 9000  | endpoint для S3 SDK, access key = root user  |
| MinIO Console | 9001  | `http://<host>:9001`                         |
| PostgreSQL    | 5432  | `postgresql://postgres:<пароль>@<host>:5432/postgres` |
| pgAdmin       | 5050  | `http://<host>:5050`, логин — PGADMIN_EMAIL          |

## Доступ снаружи

По умолчанию `BIND_IP=127.0.0.1` — порты видны только с самого сервера. Варианты:

- **SSH-туннель** (например, для веб-интерфейсов): `ssh -L 15672:127.0.0.1:15672 user@server`
- **Открыть наружу**: поставить `BIND_IP=0.0.0.0` в `.env` и обязательно ограничить доступ фаерволом, например `ufw allow from <IP приложения> to any port 27017`

## Подключение приложений из других compose-проектов

Сеть стека имеет фиксированное имя `services_backend`. В compose-файле приложения:

```yaml
services:
  app:
    networks: [services_backend]

networks:
  services_backend:
    external: true
```

Внутри сети сервисы доступны по именам сервисов: `mongodb:27017`, `redis:6379`, `rabbitmq:5672`, `minio:9000`, `postgres:5432`. Команды внутри контейнера: `docker compose exec <service> ...`.

MongoDB изнутри сети подключайте с указанием replica set:

```
mongodb://root:<пароль>@mongodb:27017/?replicaSet=rs0&authSource=admin
```

## Почему MinIO пинован на старый тег

MinIO прекратил публикацию community-образов (октябрь 2025), репозиторий заархивирован (апрель 2026). Используется `RELEASE.2025-04-22T22-12-26Z` — последний релиз с полноценной веб-консолью (пользователи, политики, access keys); в более поздних образах консоль урезана до браузера объектов. Обновлений безопасности для этого образа не будет. Если объектное хранилище критично для продакшена, рассмотрите активно поддерживаемые альтернативы: Garage, SeaweedFS, Ceph RGW или коммерческий MinIO AIStor.

## Обслуживание

```bash
docker compose logs -f <service>     # логи
docker compose pull && docker compose up -d   # обновление образов (кроме MinIO — он пинован)
docker compose down                  # остановка, данные остаются в volumes
docker compose down -v               # УДАЛИТ и данные

# бэкап volume (пример для MongoDB; аналогично для остальных)
docker run --rm -v services_mongo_data:/data -v "$PWD/backup:/backup" alpine \
  tar czf /backup/mongo_data.tgz -C /data .
```

Для консистентных бэкапов БД лучше использовать штатные инструменты: `mongodump`, `pg_dump`, `redis-cli --rdb`, `rabbitmqctl export_definitions`, `mc mirror`.

## Нюансы

- **MongoDB**: работает как single-node replica set `rs0` — транзакции и change streams доступны. keyFile для внутренней аутентификации генерируется автоматически (сервис `mongo-keyfile`), инициация набора происходит в healthcheck при первом запуске. Изнутри docker-сети подключайтесь с `?replicaSet=rs0`, снаружи (через проброшенный порт) — с `?directConnection=true`, иначе драйвер после discovery пойдёт на `mongodb:27017` из конфига набора и не достучится.
- **Redis**: включён AOF (`--appendonly yes`). Лимит памяти не задан — при необходимости добавьте `--maxmemory 512mb --maxmemory-policy allkeys-lru` в `command`.
- **PostgreSQL**: база по умолчанию называется как пользователь (`postgres`); базы под приложения создавайте отдельно. В образе 18+ том монтируется в `/var/lib/postgresql` — не меняйте на `.../data`.
- **pgAdmin**: при первом входе добавьте сервер вручную: host `postgres`, порт `5432`, пользователь и пароль — из `.env` (pgAdmin ходит к постгресу по внутренней docker-сети, поэтому именно `postgres`, а не `localhost`).
- **Лимиты ресурсов** контейнерам можно задать через `deploy.resources.limits` в compose-файле.
