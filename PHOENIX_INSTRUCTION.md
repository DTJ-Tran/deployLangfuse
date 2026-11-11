# Arize Phoenix Deployment on GCP Cloud Run — Instruction Guide

## Overview

This repo automates deploying [Arize Phoenix](https://arize.com/docs/phoenix) (LLM observability & evaluation platform) onto **GCP Cloud Run** using Git Actions.

**Stack:**
- **Phoenix** (`arizephoenix/phoenix:latest` + custom layer) — UI on port `6006`
- **Neon** (PostgreSQL serverless) — persistent database (external)
- **GCP Artifact Registry** — stores the custom Docker image
- **Modal** (serverless compute) — builds the Docker image via Kaniko (no Docker daemon needed)

**Architecture difference from Langfuse:**
Langfuse runs on a GCP VM with Docker. Phoenix runs on Cloud Run — no VM to manage, no SSH, no Docker daemon. The CI runner calls `gcloud run deploy` directly.

> **Regulated environments:** This guide uses **Modal + Kaniko** as the image build backend because it offloads heavy compute outside GCP and requires no Docker daemon on the CI runner. If your organisation requires all build activity to stay within GCP (data sovereignty, VPC controls, CMEK, audit logging), replace Modal + Kaniko with **Cloud Build + Kaniko** — see [Section 10](#10-alternative-build-backend-cloud-build-for-regulated-environments).

---

## Repository Structure

```
scripts/
  build-phoenix-image.py   # Modal + Kaniko image builder
  deploy-phoenix.sh        # gcloud run deploy script

docker/phoenix/
  Dockerfile               # Extends arizephoenix/phoenix:latest
                           # Adds sqlalchemy-cockroachdb via uv

.github/workflows/
  deploy-phoenix.yml       # CI/CD: build job → deploy job
```

---

## 1. Prerequisites

### 1.1 External services (provision before first deploy)

| Service | Purpose |
|---|---|
| Neon (PostgreSQL) | Persistent database — `PHOENIX_SQL_DATABASE_URL` |
| Modal account | Serverless build compute for Kaniko |
| GCP project | Cloud Run runtime + Artifact Registry |

### 1.2 Neon database

1. Create a project at [neon.tech](https://neon.tech)
2. Create a database named `phoenix`
3. Copy the connection string from **Dashboard → Connection string → SQLAlchemy** format

The URL must include `?sslmode=require`:
```
postgresql://user:password@ep-xxx.us-east-2.aws.neon.tech/phoenix?sslmode=require
```

---

## 2. One-Time GCP Setup

Run all commands from your **local machine** with `gcloud` authenticated.

### 2.1 Enable required APIs

```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  --project=dattrangcp
```

### 2.2 Create Artifact Registry repository

```bash
gcloud artifacts repositories create phoenix \
  --repository-format=docker \
  --location=us-central1 \
  --project=dattrangcp
```

### 2.3 Create the deploy service account

```bash
gcloud iam service-accounts create phoenix-deployer \
  --display-name="Phoenix Cloud Run Deployer" \
  --project=dattrangcp
```

### 2.4 Grant required IAM roles

```bash
# Push images to Artifact Registry
gcloud projects add-iam-policy-binding dattrangcp \
  --member="serviceAccount:phoenix-deployer@dattrangcp.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Deploy and manage Cloud Run services
gcloud projects add-iam-policy-binding dattrangcp \
  --member="serviceAccount:phoenix-deployer@dattrangcp.iam.gserviceaccount.com" \
  --role="roles/run.admin"

# Allow SA to act as itself during deployment
gcloud projects add-iam-policy-binding dattrangcp \
  --member="serviceAccount:phoenix-deployer@dattrangcp.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

### 2.5 Generate and save the service account key

```bash
gcloud iam service-accounts keys create phoenix-deployer-key.json \
  --iam-account=phoenix-deployer@dattrangcp.iam.gserviceaccount.com \
  --project=dattrangcp
```

Keep `phoenix-deployer-key.json` open — you'll need it for GitHub and Modal in the next steps.

---

## 3. Modal Setup

### 3.1 Install Modal and create tokens

```bash
pip install modal
modal token new    # opens browser → saves to ~/.modal.toml
```

### 3.2 Create Modal secret

Go to **modal.com → Secrets → Create secret**:

| Secret name | Key | Value |
|---|---|---|
| `gcp-phoenix-builder` | `GCP_SERVICE_ACCOUNT_KEY` | full JSON contents of `phoenix-deployer-key.json` |

---

## 4. GitHub Setup

Go to your repo → **Settings → Secrets and variables → Actions**.

### 4.1 Secrets (`Settings → Secrets → Actions → New repository secret`)

| Secret | Required | Value |
|---|---|---|
| `GCP_SA_KEY` | Yes | full JSON of `phoenix-deployer-key.json` |
| `GCP_PROJECT_ID` | Yes | `dattrangcp` |
| `MODAL_TOKEN_ID` | Yes | from `~/.modal.toml` or Modal dashboard |
| `MODAL_TOKEN_SECRET` | Yes | from `~/.modal.toml` or Modal dashboard |
| `PHOENIX_SECRET` | Yes | run `openssl rand -base64 32` |
| `PHOENIX_SQL_DATABASE_URL` | Yes | Neon connection string with `?sslmode=require` |
| `PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD` | No | run `openssl rand -base64 32` — if unset, Phoenix generates one |

### 4.2 Variables (`Settings → Secrets → Variables → New repository variable`)

| Variable | Value |
|---|---|
| `GCP_REGION` | `us-central1` |
| `PHOENIX_SERVICE_NAME` | `phoenix` |

### 4.3 Environment

Both jobs use the GitHub environment `langfuse_dep`. Create it under **Settings → Environments** if it doesn't exist (shared with Langfuse).

---

## 5. Cleanup Local Key File

```bash
rm phoenix-deployer-key.json
```

Never commit this file. The secret is now stored in GitHub and Modal.

---

## 6. Deployment

### 6.1 Trigger the workflow

Go to **Actions → Deploy Phoenix to Cloud Run → Run workflow**.

The workflow runs two sequential jobs:

**Job 1 — Build** (`build`):
1. Installs Modal CLI on the GitHub runner
2. Authenticates with `modal token set`
3. Runs `scripts/build-phoenix-image.py` which:
   - Spins up a Modal serverless container with Kaniko
   - Builds `docker/phoenix/Dockerfile` on top of `arizephoenix/phoenix:latest`
   - Pushes the image to `us-central1-docker.pkg.dev/<project>/phoenix/phoenix:latest`

**Job 2 — Deploy** (`deploy`, runs after build):
1. Authenticates to GCP via service account key
2. Runs `scripts/deploy-phoenix.sh` which:
   - Writes env vars to `/tmp/phoenix-env.yaml`
   - Calls `gcloud run deploy` targeting the Artifact Registry image

### 6.2 Access Phoenix

After a successful deploy:

```bash
gcloud run services describe phoenix \
  --region=us-central1 \
  --project=dattrangcp \
  --format="value(status.url)"
```

### 6.3 First login

| Field | Value |
|---|---|
| Email | `admin@localhost` |
| Password | value of `PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD` secret |

If `PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD` was not set, fetch the auto-generated password from logs:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="phoenix"' \
  --project=dattrangcp \
  --limit=200 \
  --order=asc \
  --format="value(textPayload)" \
| grep -i "password\|admin\|created"
```

---

## 7. Sending Traces to Phoenix

Point your instrumented app at the Cloud Run service URL:

```python
# OTLP over HTTP (use this — gRPC port 4317 is not reachable on Cloud Run)
PHOENIX_ENDPOINT = "https://<your-service>.a.run.app/v1/traces"
```

---

## 8. Verifying the Deployment

Check the Cloud Run service status:

```bash
gcloud run services describe phoenix \
  --region=us-central1 \
  --project=dattrangcp \
  --format="yaml(status.conditions)"
```

Tail live logs:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="phoenix"' \
  --project=dattrangcp \
  --limit=50 \
  --order=desc \
  --format="value(textPayload)"
```

Verify env vars reached the container (check DB is not SQLite):

```bash
gcloud run services describe phoenix \
  --region=us-central1 \
  --project=dattrangcp \
  --format="yaml(spec.template.spec.containers[0].env)"
```

The startup banner should show:
```
Database    postgresql://...   ✅  (not sqlite://)
Authentication    ✅ Enabled
```

---

## 9. Caveats and Common Mistakes

### Cloud Run is not a VM — no SSH, no Docker daemon

There is no VM involved in the Phoenix deployment. The build runs on Modal (serverless), the image is stored in Artifact Registry, and the runtime is Cloud Run. You cannot SSH into the container.

### OTLP gRPC port 4317 is not reachable externally

Cloud Run only exposes one port publicly (port `6006`). The gRPC OTLP port `4317` is configured inside the container but unreachable from outside. Always use **OTLP over HTTP** (`/v1/traces` on port `6006`) for trace ingestion.

### Database migrations block startup — startup probe timeout

Phoenix runs Alembic migrations on first boot. On a fresh database this can take 2–5 minutes. The startup probe is configured as:

```
initialDelaySeconds=10, periodSeconds=30, failureThreshold=20
```

This gives a **10-minute total budget**. If migrations are still timing out, increase `failureThreshold` in `deploy-phoenix.sh`.

> Never revert to Cloud Run's default probe (1 attempt × 4 min) — it will always fail on first deploy against a fresh database.

### `PHOENIX_SQL_DATABASE_URL` missing = silent SQLite fallback

If `PHOENIX_SQL_DATABASE_URL` is missing or empty, Phoenix silently falls back to `sqlite:////root/.phoenix/phoenix.db`. Since Cloud Run's filesystem is **ephemeral**, all data is lost on every redeploy or instance restart.

Always verify the startup banner shows `postgresql://` not `sqlite://` after each deploy.

### `PHOENIX_SECRET` requirements

`PHOENIX_SECRET` must be:
- At least 32 characters
- Contain at least one digit and one lowercase letter

Changing it after first deploy **invalidates all existing sessions and API keys**.

### Neon connection string must include `?sslmode=require`

Neon rejects connections without SSL. The individual `PHOENIX_POSTGRES_*` env vars have no SSL field — always use the full `PHOENIX_SQL_DATABASE_URL` with `?sslmode=require` appended.

### `--max-instances=1` is intentional

Phoenix is not designed to run as multiple replicas against the same database. Cloud Run scaling to 2+ instances causes write conflicts. Keep `--max-instances=1`.

### `--min-instances=1` cost

Keeping one instance always warm (no cold starts) costs ~**$7/month** (1Gi memory, 1 CPU, us-central1). Removing `--min-instances=1` saves cost but introduces cold starts and drops OTLP traces sent while the instance is cold — unacceptable for an observability tool.

### `uv` not `pip` for installing packages into Phoenix venv

The Phoenix image manages its venv with `uv`. Using `pip install` or `python -m ensurepip` corrupts the venv and removes SQLAlchemy, breaking startup. Always use:

```dockerfile
RUN uv pip install --python /phoenix/.venv --no-cache <package>
```

### Kaniko `--no-cache` vs pip `--no-cache-dir`

`uv`'s flag is `--no-cache` (not `--no-cache-dir` which is pip's flag). Using the wrong flag causes the build to fail with a "required argument not provided" error.

### Modal `add_local_dir` bakes context at image build time

`docker/phoenix/` is baked into the Modal builder image when `modal run` executes. If you change the Dockerfile locally, you must re-run the workflow — the old Modal image cache will be used until the builder image is rebuilt. Modal rebuilds the image automatically when `add_local_dir` content changes.

### Two separate token systems: Modal and GCP

| System | Auth method | Where stored |
|---|---|---|
| Modal (build) | `MODAL_TOKEN_ID` + `MODAL_TOKEN_SECRET` | GitHub Secrets |
| GCP (deploy) | `GCP_SA_KEY` JSON | GitHub Secrets |
| Modal (Kaniko → AR push) | `GCP_SERVICE_ACCOUNT_KEY` | Modal Secret `gcp-phoenix-builder` |

The GCP service account key appears in **two places**: GitHub (for `gcloud run deploy`) and Modal (for Kaniko to push to Artifact Registry). Keep both in sync when rotating keys.

---

## 10. Alternative Build Backend: Cloud Build (for Regulated Environments)

Use this instead of Modal + Kaniko when:

| Requirement | Why Cloud Build wins |
|---|---|
| Data must not leave GCP | Modal runs on external infrastructure; Cloud Build runs inside your GCP project |
| VPC Service Controls | Cloud Build supports VPC-SC; Modal does not |
| CMEK (customer-managed encryption) | Cloud Build supports CMEK for build artifacts |
| Centralised GCP audit logs | Every build step is logged in Cloud Audit Logs automatically |
| No external SaaS tokens | Removes `MODAL_TOKEN_ID` / `MODAL_TOKEN_SECRET` from the secret surface |

### 10.1 How it works

Replace the Modal build step with `gcloud builds submit`, which runs Kaniko natively inside Cloud Build:

```
GitHub Actions runner
  → gcloud builds submit --config=cloudbuild.yaml
      → Cloud Build runs Kaniko inside GCP
          → pushes image → Artifact Registry
  → gcloud run deploy
```

### 10.2 Add `cloudbuild.yaml` to the repo root

```yaml
steps:
  - name: gcr.io/kaniko-project/executor:latest
    args:
      - --dockerfile=docker/phoenix/Dockerfile
      - --context=.
      - --destination=us-central1-docker.pkg.dev/$PROJECT_ID/phoenix/phoenix:latest
      - --cache=true
      - --cache-repo=us-central1-docker.pkg.dev/$PROJECT_ID/phoenix/cache
      - --custom-platform=linux/amd64
      - --verbosity=info

options:
  machineType: E2_HIGHCPU_8
  logging: CLOUD_LOGGING_ONLY
```

### 10.3 Additional IAM roles (one-time)

```bash
# Allow the SA to submit Cloud Build jobs
gcloud projects add-iam-policy-binding dattrangcp \
  --member="serviceAccount:phoenix-deployer@dattrangcp.iam.gserviceaccount.com" \
  --role="roles/cloudbuild.builds.editor"

# Cloud Build's own SA needs to push to Artifact Registry
PROJECT_NUMBER=$(gcloud projects describe dattrangcp --format="value(projectNumber)")
gcloud projects add-iam-policy-binding dattrangcp \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Enable Cloud Build API
gcloud services enable cloudbuild.googleapis.com --project=dattrangcp
```

### 10.4 Replace the `build` job in `deploy-phoenix.yml`

```yaml
build:
  name: Build image (Cloud Build + Kaniko)
  runs-on: ubuntu-latest
  environment: langfuse_dep

  steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Authenticate to Google Cloud
      uses: google-github-actions/auth@v2
      with:
        credentials_json: ${{ secrets.GCP_SA_KEY }}

    - name: Set up gcloud CLI
      uses: google-github-actions/setup-gcloud@v2

    - name: Build & push Phoenix image (Cloud Build)
      run: |
        gcloud builds submit . \
          --config=cloudbuild.yaml \
          --region=us-central1 \
          --project=${{ secrets.GCP_PROJECT_ID }} \
          --substitutions=_TAG=latest
```

### 10.5 Secrets comparison

| Secret | Modal approach | Cloud Build approach |
|---|---|---|
| `MODAL_TOKEN_ID` | Required | **Remove** |
| `MODAL_TOKEN_SECRET` | Required | **Remove** |
| `GCP_SA_KEY` | Required | Required (same) |
| `GCP_PROJECT_ID` | Required | Required (same) |
| Modal secret `gcp-phoenix-builder` | Required | **Remove** |

Cloud Build eliminates the two Modal token secrets and the Modal secret entirely — the GCP service account key already in GitHub is sufficient for both build and deploy.

### 10.6 Cost

Cloud Build free tier includes **120 build-minutes/day**. The Phoenix image build takes ~3–5 minutes. For infrequent deploys this is effectively free. Beyond the free tier: ~$0.003/build-minute on `E2_HIGHCPU_8`.
