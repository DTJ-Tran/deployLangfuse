#!/bin/bash
set -euo pipefail

LANGFUSE_IMAGE="langfuse/langfuse:2.24.1"
LANGFUSE_CONTAINER="langfuse-web"
LANGFUSE_PORT="${LANGFUSE_PORT:-3000}"
LANGFUSE_HOSTNAME="${LANGFUSE_HOSTNAME:-0.0.0.0}"
NETWORK="langfuse-net"

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
  -e DATABASE_URL="$DATABASE_URL" \
  \
  -e NEXTAUTH_URL="$NEXTAUTH_URL" \
  -e NEXTAUTH_SECRET="$NEXTAUTH_SECRET" \
  -e SALT="$SALT" \
  \
  -e TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-false}" \
  -e LANGFUSE_DEFAULT_PROJECT_ROLE="${LANGFUSE_DEFAULT_PROJECT_ROLE:-VIEWER}" \
  \
  "$LANGFUSE_IMAGE"

echo ">>> Done. Running containers:"
docker ps --filter "name=langfuse" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
