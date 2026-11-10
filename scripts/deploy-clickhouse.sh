#!/bin/bash
set -euo pipefail

CLICKHOUSE_IMAGE="clickhouse/clickhouse-server:latest"
CLICKHOUSE_CONTAINER="clickhouse"
NETWORK="langfuse-net"

echo ">>> Ensuring Docker network: $NETWORK"
docker network create "$NETWORK" 2>/dev/null || true

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

echo ">>> Done. ClickHouse status:"
docker ps --filter "name=clickhouse" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
