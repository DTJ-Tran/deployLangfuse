#!/bin/bash
set -euo pipefail

LANGFUSE_IMAGE="langfuse/langfuse:3.227"
LANGFUSE_CONTAINER="langfuse-web"
NETWORK="langfuse-net"

LANGFUSE_PORT="${LANGFUSE_PORT:-3000}"
LANGFUSE_HOSTNAME="${LANGFUSE_HOSTNAME:-0.0.0.0}"

# Internal ClickHouse URLs (resolved via Docker network)
CLICKHOUSE_URL="http://clickhouse:8123"
CLICKHOUSE_MIGRATION_URL="clickhouse://default:${CLICKHOUSE_PASSWORD}@clickhouse:9000"

echo ">>> Ensuring Docker network: $NETWORK"
docker network create "$NETWORK" 2>/dev/null || true

echo ">>> Pulling $LANGFUSE_IMAGE"
docker pull "$LANGFUSE_IMAGE"

echo ">>> Restarting $LANGFUSE_CONTAINER"
docker stop "$LANGFUSE_CONTAINER" 2>/dev/null || true
docker rm   "$LANGFUSE_CONTAINER" 2>/dev/null || true

docker run -d \
  --name "$LANGFUSE_CONTAINER" \
  --network "$NETWORK" \
  --restart unless-stopped \
  -p "${LANGFUSE_PORT}:${LANGFUSE_PORT}" \
  \
  -e PORT="$LANGFUSE_PORT" \
  -e HOSTNAME="$LANGFUSE_HOSTNAME" \
  \
  -e DATABASE_URL="$DATABASE_URL" \
  \
  -e NEXTAUTH_URL="$NEXTAUTH_URL" \
  -e NEXTAUTH_SECRET="$NEXTAUTH_SECRET" \
  -e SALT="$SALT" \
  -e ENCRYPTION_KEY="$ENCRYPTION_KEY" \
  \
  -e REDIS_HOST="$REDIS_HOST" \
  -e REDIS_PORT="$REDIS_PORT" \
  -e REDIS_AUTH="$REDIS_AUTH" \
  -e REDIS_TLS_ENABLED="true" \
  \
  -e CLICKHOUSE_URL="$CLICKHOUSE_URL" \
  -e CLICKHOUSE_MIGRATION_URL="$CLICKHOUSE_MIGRATION_URL" \
  -e CLICKHOUSE_USER="$CLICKHOUSE_USER" \
  -e CLICKHOUSE_PASSWORD="$CLICKHOUSE_PASSWORD" \
  -e CLICKHOUSE_CLUSTER_ENABLED="false" \
  \
  -e LANGFUSE_S3_EVENT_UPLOAD_ENABLED="true" \
  -e LANGFUSE_S3_EVENT_UPLOAD_BUCKET="$LANGFUSE_S3_EVENT_UPLOAD_BUCKET" \
  -e LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT="$LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT" \
  -e LANGFUSE_S3_EVENT_UPLOAD_REGION="auto" \
  -e LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID="$LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID" \
  -e LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY="$LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY" \
  -e LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE="true" \
  \
  -e TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-false}" \
  \
  "$LANGFUSE_IMAGE"

echo ">>> Done. Web UI status:"
docker ps --filter "name=langfuse-web" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
