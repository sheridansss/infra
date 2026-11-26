# PostgreSQL 18.6 / Alpine 3.24: обновляем Brotli для CVE-2026-111497.
# Удалить этот слой, когда официальный образ содержит исправленный пакет.
# Штатный entrypoint подготавливает том от root, затем делает exec gosu postgres
# (проверено: PID 1 работает с UID 70). HEALTHCHECK задан в docker-compose.yml.
# KICS не учитывает унаследованный entrypoint и healthcheck Compose.
# kics-scan ignore-line
FROM postgres:18.7-alpine3.24@sha256:0115267ab5a509022df9319c77be365cef335adb71556c75f60f5360ee247e71

RUN apk add --no-cache 'brotli-libs=1.2.1-r0'

LABEL org.opencontainers.image.source="https://github.com/sheridansss/infra"
