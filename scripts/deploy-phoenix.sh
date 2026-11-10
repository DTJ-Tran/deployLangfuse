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

# Use ^|^ as delimiter so the PostgreSQL URL (which contains = and @) doesn't
# confuse the comma-delimited --set-env-vars parser.
gcloud run deploy "$SERVICE_NAME" \
  --image="$PHOENIX_IMAGE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --port=6006 \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=1 \
  --memory=512Mi \
  --cpu=1 \
  --set-env-vars="^|^PHOENIX_PORT=6006|PHOENIX_GRPC_PORT=4317|PHOENIX_ENABLE_AUTH=true|PHOENIX_USE_SECURE_COOKIES=true|PHOENIX_TELEMETRY_ENABLED=false|PHOENIX_SECRET=${PHOENIX_SECRET}|PHOENIX_SQL_DATABASE_URL=${PHOENIX_SQL_DATABASE_URL}"

echo ">>> Done. Service URL:"
gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT" \
  --format="value(status.url)"
