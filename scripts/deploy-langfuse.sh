#!/bin/bash
set -euo pipefail

LANGFUSE_IMAGE="langfuse/langfuse:4"
WORKER_IMAGE="langfuse/langfuse-worker:4"
CLICKHOUSE_IMAGE="clickhouse/clickhouse-server:latest"

LANGFUSE_CONTAINER="langfuse-web"
WORKER_CONTAINER="langfuse-worker"
CLICKHOUSE_CONTAINER="clickhouse"
NETWORK="langfuse-net"

# Container-internal ClickHouse URLs (resolved via Docker network)
CLICKHOUSE_INTERNAL_URL="http://clickhouse:8123"
CLICKHOUSE_MIGRATION_URL="clickhouse://default:${CLICKHOUSE_PASSWORD}@clickhouse:9000"

# --- Docker network ---
echo ">>> Ensuring Docker network: $NETWORK"
docker network create "$NETWORK" 2>/dev/null || true

# --- ClickHouse ---
echo ">>> Starting ClickHouse"
if [ "$(docker ps -q -f name=^${CLICKHOUSE_CONTAINER}$)" ]; then
  echo "    ClickHouse already running — skipping"
else
  docker stop "$CLICKHOUSE_CONTAINER" 2>/dev/null || true
  docker rm   "$CLICKHOUSE_CONTAINER" 2>/dev/null || true

  docker run -d \
    --name "$CLICKHOUSE_CONTAINER" \
    --network "$NETWORK" \
    --restart unless-stopped \
    -p 8123:8123 \
    -p 9000:9000 \
    -e CLICKHOUSE_USER="$CLICKHOUSE_USER" \
    -e CLICKHOUSE_PASSWORD="$CLICKHOUSE_PASSWORD" \
    -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    -v clickhouse-data:/var/lib/clickhouse \
    --ulimit nofile=262144:262144 \
    "$CLICKHOUSE_IMAGE"

  echo "    Waiting for ClickHouse to be ready..."
  sleep 15
fi

# --- Langfuse Web ---
echo ">>> Pulling $LANGFUSE_IMAGE"
docker pull "$LANGFUSE_IMAGE"

echo ">>> Restarting $LANGFUSE_CONTAINER"
docker stop "$LANGFUSE_CONTAINER" 2>/dev/null || true
docker rm   "$LANGFUSE_CONTAINER" 2>/dev/null || true

docker run -d \
  --name "$LANGFUSE_CONTAINER" \
  --network "$NETWORK" \
  --restart unless-stopped \
  -p 3000:3000 \
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
  "$LANGFUSE_IMAGE"

# --- Langfuse Worker ---
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

echo ">>> Done. Running containers:"
docker ps --filter "name=langfuse" --filter "name=clickhouse" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
