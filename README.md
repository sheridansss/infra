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

## Деплой на сервер

Сервер за VPN, поэтому деплой — pull-моделью: сервер сам подтягивает `main` по systemd-таймеру. GitHub Actions остаётся только для CI (`deploy.yml` заготовлен на случай, если сервер станет доступен раннерам).

Первичная установка (один раз, на сервере):

```bash
sudo mkdir -p /opt/infra && sudo chown "$USER" /opt/infra
git clone https://github.com/sheridansss/infra.git /opt/infra
cd /opt/infra
bash generate-env.sh                 # пароли; при необходимости поправьте BIND_IP/порты
docker compose up -d --wait
bash deploy/install-autodeploy.sh    # systemd-таймер автодеплоя (по умолчанию каждые 2 мин)
```

Дальше каждый push в `main` приезжает на сервер в течение пары минут. Автодеплой не трогает `.env` и `backup/` (они не в git) и ничего не удаляет. Логи: `journalctl -u infra-autodeploy.service -f`.

Задеплоить немедленно, не дожидаясь таймера (с машины с VPN-доступом):

```bash
bash deploy/deploy-now.sh user@server           # Linux/macOS/Git Bash
.\deploy\deploy-now.ps1 -Server user@server     # Windows PowerShell
```

## Бэкапы и восстановление

Два скрипта под разные задачи:

- **`backup.sh`** — регулярный онлайн-бэкап штатными инструментами, стек продолжает работать: `mongodump --oplog`, `pg_dumpall`, RDB-снапшот Redis, definitions RabbitMQ (пользователи, vhosts, очереди, биндинги — сообщения не бэкапятся), зеркало бакетов MinIO. Результат — `backup/<дата_время>/`, хранятся последние 7 копий (число — переменной `BACKUP_KEEP`).
- **`backup-cold.sh`** — холодный бэкап: останавливает стек и архивирует все volumes 1-в-1, включая то, чего нет в онлайн-бэкапе (настройки pgAdmin, IAM-пользователи и политики MinIO). Для переезда на другой сервер и точки отката перед мажорным обновлением. Ротации нет — каталоги `backup/cold-*` удаляются вручную.

Ночной бэкап по systemd-таймеру (на сервере, по умолчанию в 03:30):

```bash
bash deploy/install-backup-timer.sh        # своё расписание: ... "*-*-* 04:00:00"
```

Каталог `backup/` не в git и автодеплоем не затрагивается.

### Выгрузка наружу

Бэкап на том же диске не защищает от гибели сервера. Задайте `BACKUP_REMOTE` в `.env` — и каждый запуск `backup.sh` (в том числе по таймеру) будет заканчиваться зеркалированием `backup/` во внешнее хранилище; вручную — `bash backup-sync.sh`:

```bash
BACKUP_REMOTE=s3:bucket/infra-backup    # rclone-remote: сначала rclone config на сервере
BACKUP_REMOTE=user@host:/backups/infra  # rsync по SSH: ключ без пароля, каталог должен существовать
BACKUP_REMOTE=/mnt/nas/infra            # rsync в примонтированный каталог (NAS)
```

Это зеркало 1-в-1: ротация применяется и к удалённой копии, удалённый локально `cold-*` исчезнет и там. Пустой локальный `backup/` внешнюю копию не затирает — скрипт откажется выгружать. Дампы содержат данные БД, поэтому хранилище должно быть приватным.

Вернуть бэкапы на новый сервер: `rclone copy s3:bucket/infra-backup backup/` либо `rsync -a user@host:/backups/infra/ backup/`.

### Восстановление из backup.sh

Штатный путь — `restore.sh`: он повторяет проверенные процедуры и перед началом показывает, что будет перезаписано, с подтверждением (`--yes` — для неинтерактивного запуска):

```bash
bash restore.sh latest                                 # весь стек из свежайшей копии
bash restore.sh backup/2026-07-30_233443 redis postgres  # выборочно, из конкретной
```

По сервисам: MongoDB — `mongorestore --drop --oplogReplay` (коллекции заменяются); PostgreSQL — пересоздание кластера (volume) и загрузка `pg_dumpall` (сообщение `role "postgres" already exists` — норма); Redis — загрузка RDB-снапшота одноразовым сервером без AOF с последующим включением AOF (при включённом AOF Redis игнорирует `dump.rdb`, даже когда AOF-файлов нет); RabbitMQ — `rabbitmqctl import_definitions` поверх текущих; MinIO — `mc mirror --overwrite` поверх текущих.

Этот же цикл «бэкап → потеря данных → restore.sh → проверка» CI гоняет на каждом коммите.

Нестандартные случаи (одна база или коллекция, перенос на другую машину) — штатными инструментами вручную: `mongorestore --nsInclude ...`, `psql -d <база>`, `mc mirror local/<бакет> ...`; готовые последовательности команд — внутри `restore.sh`.

### Восстановление из backup-cold.sh

На чистом сервере сначала создайте volumes: `docker compose up -d && docker compose down`. Затем:

```bash
docker compose down
for f in backup/cold-<дата>/*.tgz; do
  vol=$(basename "$f" .tgz)
  docker run --rm -i -v "$vol:/restore" alpine:3 \
    sh -c 'find /restore -mindepth 1 -delete && tar -xzf - -C /restore' < "$f"
done
docker compose up -d --wait
```

## Почему MinIO пинован на старый тег

MinIO прекратил публикацию community-образов (октябрь 2025), репозиторий заархивирован (апрель 2026). Используется `RELEASE.2025-04-22T22-12-26Z` — последний релиз с полноценной веб-консолью (пользователи, политики, access keys); в более поздних образах консоль урезана до браузера объектов. Обновлений безопасности для этого образа не будет. Если объектное хранилище критично для продакшена, рассмотрите активно поддерживаемые альтернативы: Garage, SeaweedFS, Ceph RGW или коммерческий MinIO AIStor.

## Обслуживание

```bash
docker compose logs -f <service>     # логи
docker compose pull && docker compose up -d   # обновление образов (кроме MinIO — он пинован)
docker compose down                  # остановка, данные остаются в volumes
docker compose down -v               # УДАЛИТ и данные
```

Бэкапы — `backup.sh` и `backup-cold.sh`, см. раздел выше.

## Нюансы

- **MongoDB**: работает как single-node replica set `rs0` — транзакции и change streams доступны. keyFile для внутренней аутентификации генерируется автоматически (сервис `mongo-keyfile`), инициация набора происходит в healthcheck при первом запуске. Изнутри docker-сети подключайтесь с `?replicaSet=rs0`, снаружи (через проброшенный порт) — с `?directConnection=true`, иначе драйвер после discovery пойдёт на `mongodb:27017` из конфига набора и не достучится.
- **Redis**: включён AOF (`--appendonly yes`). Лимит памяти не задан — при необходимости добавьте `--maxmemory 512mb --maxmemory-policy allkeys-lru` в `command`.
- **PostgreSQL**: база по умолчанию называется как пользователь (`postgres`); базы под приложения создавайте отдельно. В образе 18+ том монтируется в `/var/lib/postgresql` — не меняйте на `.../data`.
- **pgAdmin**: при первом входе добавьте сервер вручную: host `postgres`, порт `5432`, пользователь и пароль — из `.env` (pgAdmin ходит к постгресу по внутренней docker-сети, поэтому именно `postgres`, а не `localhost`).
- **Лимиты ресурсов** контейнерам можно задать через `deploy.resources.limits` в compose-файле.
