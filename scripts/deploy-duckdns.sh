#!/bin/bash
set -euo pipefail

CONTAINER="duckdns"
IMAGE="lscr.io/linuxserver/duckdns:latest"

echo ">>> Pulling DuckDNS image"
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
