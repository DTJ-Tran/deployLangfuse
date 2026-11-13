#!/bin/bash
set -euo pipefail

CONTAINER="duckdns"
IMAGE="${DUCKDNS_IMAGE:?DUCKDNS_IMAGE must be set to the Artifact Registry path, e.g. us-central1-docker.pkg.dev/<proj>/mirror/duckdns:<tag>}"

echo ">>> Pulling DuckDNS image: $IMAGE"
docker pull "$IMAGE"

echo ">>> Stopping existing DuckDNS container (if any)"
docker stop "$CONTAINER" 2>/dev/null || true
docker rm   "$CONTAINER" 2>/dev/null || true

echo ">>> Starting DuckDNS updater"
docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -e SUBDOMAINS="$DUCKDNS_SUBDOMAIN" \
  -e TOKEN="$DUCKDNS_TOKEN" \
  -e UPDATE_IP=ipv4 \
  -e TZ=Asia/Ho_Chi_Minh \
  -v duckdns-config:/config \
  "$IMAGE"

echo ">>> Waiting for first IP update..."
sleep 5

echo ">>> DuckDNS status:"
docker logs "$CONTAINER"
