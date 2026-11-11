#!/bin/bash
set -euo pipefail

PHOENIX_IMAGE="us-central1-docker.pkg.dev/${GCP_PROJECT_ID}/phoenix/phoenix:latest"
SERVICE_NAME="${PHOENIX_SERVICE_NAME:-phoenix}"
REGION="${GCP_REGION:-us-central1}"
PROJECT="${GCP_PROJECT_ID}"

echo ">>> Deploying Phoenix to Cloud Run"
echo "    Service : $SERVICE_NAME"
echo "    Region  : $REGION"
echo "    Project : $PROJECT"
echo "    Image   : $PHOENIX_IMAGE"

# Validate required secrets are present before attempting deploy.
: "${PHOENIX_SECRET:?PHOENIX_SECRET is not set — add it to GitHub Secrets}"
: "${PHOENIX_SQL_DATABASE_URL:?PHOENIX_SQL_DATABASE_URL is not set — add it to GitHub Secrets}"

# Optional — if unset, Phoenix generates a random password on first boot.
PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD="${PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD:-}"

# Write env vars to a YAML file so values with special chars (@ : = |) are safe.
# Neon requires SSL — the full URL with ?sslmode=require covers this;
# individual PHOENIX_POSTGRES_* vars have no SSL field.
cat > /tmp/phoenix-env.yaml << EOF
PHOENIX_PORT: "6006"
PHOENIX_GRPC_PORT: "4317"
PHOENIX_ENABLE_AUTH: "true"
PHOENIX_USE_SECURE_COOKIES: "true"
PHOENIX_TELEMETRY_ENABLED: "false"
PHOENIX_SECRET: "${PHOENIX_SECRET}"
PHOENIX_SQL_DATABASE_URL: "${PHOENIX_SQL_DATABASE_URL}"
PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD: "${PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD}"
EOF

gcloud run deploy "$SERVICE_NAME" \
  --image="$PHOENIX_IMAGE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --port=6006 \
  --allow-unauthenticated \
  --min-instances=1 \
  --max-instances=1 \
  --memory=1Gi \
  --cpu=1 \
  --cpu-boost \
  --timeout=300 \
  --startup-probe=tcpSocket.port=6006,initialDelaySeconds=10,periodSeconds=30,failureThreshold=20 \
  --env-vars-file=/tmp/phoenix-env.yaml

echo ">>> Done. Service URL:"
gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(status.url)"
