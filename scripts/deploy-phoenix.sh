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
# PHOENIX_MIGRATE_INDEX_CONCURRENTLY: migrations use CREATE INDEX CONCURRENTLY
# so no table locks during the migration job.
cat > /tmp/phoenix-env.yaml << EOF
PHOENIX_PORT: "6006"
PHOENIX_GRPC_PORT: "4317"
PHOENIX_ENABLE_AUTH: "true"
PHOENIX_USE_SECURE_COOKIES: "true"
PHOENIX_TELEMETRY_ENABLED: "false"
PHOENIX_SECRET: "${PHOENIX_SECRET}"
PHOENIX_SQL_DATABASE_URL: "${PHOENIX_SQL_DATABASE_URL}"
PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD: "${PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD}"
PHOENIX_MIGRATE_INDEX_CONCURRENTLY: "true"
EOF

# --- Step 1: Run DB migrations as a Cloud Run Job ---
# This separates migration from server startup so the Cloud Run startup probe
# never times out waiting for Alembic to finish.
echo ">>> Running DB migrations (Cloud Run Job)"
gcloud run jobs create phoenix-migrate \
  --image="$PHOENIX_IMAGE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --command="phoenix" \
  --args="db,migrate" \
  --env-vars-file=/tmp/phoenix-env.yaml \
  --max-retries=1 \
  --task-timeout=600 \
  2>/dev/null \
|| gcloud run jobs update phoenix-migrate \
  --image="$PHOENIX_IMAGE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --command="phoenix" \
  --args="db,migrate" \
  --env-vars-file=/tmp/phoenix-env.yaml \
  --max-retries=1 \
  --task-timeout=600

echo ">>> Executing migration job (waiting for completion)..."
gcloud run jobs execute phoenix-migrate \
  --region="$REGION" \
  --project="$PROJECT" \
  --wait

echo ">>> Migrations complete."

# --- Step 2: Deploy the service (DB already migrated) ---
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
