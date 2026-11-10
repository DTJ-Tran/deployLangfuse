#!/bin/bash
set -euo pipefail

WORKER_IMAGE="langfuse/langfuse-worker:4"
WORKER_CONTAINER="langfuse-worker"
NETWORK="langfuse-net"

CLICKHOUSE_INTERNAL_URL="http://clickhouse:8123"
CLICKHOUSE_MIGRATION_URL="clickhouse://default:${CLICKHOUSE_PASSWORD}@clickhouse:9000"

echo ">>> Pulling $WORKER_IMAGE"
docker pull "$WORKER_IMAGE"

echo ">>> Restarting $WORKER_CONTAINER"
docker stop "$WORKER_CONTAINER" 2>/dev/null || true
docker rm   "$WORKER_CONTAINER" 2>/dev/null || true

docker run -d \
  --name "$WORKER_CONTAINER" \
  --network "$NETWORK" \
  --restart unless-stopped \
  \
  -e DATABASE_URL="$DATABASE_URL" \
  \
  -e SALT="$SALT" \
  -e ENCRYPTION_KEY="$ENCRYPTION_KEY" \
  \
  -e REDIS_HOST="$REDIS_HOST" \
  -e REDIS_PORT="$REDIS_PORT" \
  -e REDIS_AUTH="$REDIS_AUTH" \
  -e REDIS_TLS_ENABLED="true" \
  \
  -e CLICKHOUSE_URL="$CLICKHOUSE_INTERNAL_URL" \
  -e CLICKHOUSE_MIGRATION_URL="$CLICKHOUSE_MIGRATION_URL" \
  -e CLICKHOUSE_USER="$CLICKHOUSE_USER" \
  -e CLICKHOUSE_PASSWORD="$CLICKHOUSE_PASSWORD" \
  \
  -e LANGFUSE_S3_EVENT_UPLOAD_BUCKET="$LANGFUSE_S3_EVENT_UPLOAD_BUCKET" \
  -e LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT="$LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT" \
  -e LANGFUSE_S3_EVENT_UPLOAD_REGION="auto" \
  -e LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID="$LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID" \
  -e LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY="$LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY" \
  \
  "$WORKER_IMAGE"

echo ">>> Done. Worker status:"
docker ps --filter "name=langfuse-worker" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
