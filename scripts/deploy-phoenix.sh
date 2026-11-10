#!/bin/bash
set -euo pipefail

PHOENIX_IMAGE="arizephoenix/phoenix:latest"
SERVICE_NAME="${PHOENIX_SERVICE_NAME:-phoenix}"
REGION="${GCP_REGION:-us-central1}"
PROJECT="${GCP_PROJECT_ID}"

echo ">>> Deploying Phoenix to Cloud Run"
echo "    Service : $SERVICE_NAME"
echo "    Region  : $REGION"
echo "    Project : $PROJECT"
echo "    Image   : $PHOENIX_IMAGE"

# Write env vars to a YAML file so values with special chars (@ : = |) are safe.
cat > /tmp/phoenix-env.yaml << EOF
PHOENIX_PORT: "6006"
PHOENIX_GRPC_PORT: "4317"
PHOENIX_ENABLE_AUTH: "true"
PHOENIX_USE_SECURE_COOKIES: "true"
PHOENIX_TELEMETRY_ENABLED: "false"
PHOENIX_SECRET: "${PHOENIX_SECRET}"
PHOENIX_SQL_DATABASE_URL: "${PHOENIX_SQL_DATABASE_URL}"
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
  --env-vars-file=/tmp/phoenix-env.yaml

echo ">>> Done. Service URL:"
gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(status.url)"
