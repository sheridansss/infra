# PostgreSQL 18.6 / Alpine 3.24: обновляем Brotli для CVE-2026-111497.
# Удалить этот слой, когда официальный образ содержит исправленный пакет.
# Штатный entrypoint подготавливает том от root, затем делает exec gosu postgres
# (проверено: PID 1 работает с UID 70). HEALTHCHECK задан в docker-compose.yml.
# KICS не учитывает унаследованный entrypoint и healthcheck Compose.
# kics-scan ignore-line
FROM postgres:18.6-alpine3.24@sha256:9ba53c7d41ea093baf5c1ba635ba5434c4f979880527d49bb7d9237d3193085b

RUN apk add --no-cache 'brotli-libs=1.2.1-r0'

LABEL org.opencontainers.image.source="https://github.com/sheridansss/infra"
