# Langfuse Deployment on GCP VM — Instruction Guide

## Overview

This repo automates deploying [Langfuse](https://langfuse.com) (LLM observability platform) onto a GCP VM using GitHub Actions over SSH.

**Stack:**
- **Langfuse Web** (`langfuse/langfuse:4`) — UI on port `3000`
- **Langfuse Worker** (`langfuse/langfuse-worker:4`) — background job processor
- **ClickHouse** (`clickhouse/clickhouse-server:latest`) — event analytics DB, runs locally on the VM
- **CockroachDB** (Cockroach Cloud) — primary relational DB (external)
- **Upstash Redis** — job queue / cache (external)
- **GCS bucket** — S3-compatible event upload storage (external)
- **DuckDNS** — dynamic DNS updater (optional, maps domain to VM IP)

---

## 1. Prerequisites

### GCP VM
- Debian-based VM (e.g., Debian 11/12)
- At least 2 vCPU / 4 GB RAM recommended for ClickHouse + two Langfuse containers
- A static or note of the external IP

### Local tools
- `gcloud` CLI authenticated (`gcloud auth login`)
- SSH access to the VM

### External services (must be provisioned beforehand)
| Service | Purpose |
|---|---|
| CockroachDB Cloud | Primary database (`DATABASE_URL`) |
| Upstash Redis | Queue and cache (`REDIS_HOST`, `REDIS_PORT`, `REDIS_AUTH`) |
| GCS bucket | Event upload storage (`LANGFUSE_S3_EVENT_UPLOAD_*`) |
| DuckDNS (optional) | Dynamic DNS (`DUCKDNS_TOKEN`, `DUCKDNS_SUBDOMAIN`) |

---

## 2. First-Time VM Setup

### 2.1 SSH into the VM

```bash
gcloud auth login
gcloud compute ssh dat-tran-vm --zone=us-central1-a --project=dattrangcp
```

### 2.2 Install Docker

Run each block from `secrets/install_docker.sh`:

```bash
sudo apt-get remove -y docker docker-engine docker.io containerd runc
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 2.3 Add deploy user to Docker group

So the GitHub Actions SSH user (`davestran`) can run Docker without `sudo`:

```bash
sudo usermod -aG docker davestran
# Log out and back in (or newgrp docker) for the group change to take effect
```

### 2.4 Configure the firewall (UFW)

> **CRITICAL — always open port 22 BEFORE enabling UFW, or you will lock yourself out.**

```bash
sudo apt install ufw          # install if not present

sudo ufw allow 22/tcp         # SSH — MUST be first
sudo ufw allow 3000/tcp       # Langfuse Web UI

sudo ufw enable               # type 'y' when prompted — SSH rule is already in place
sudo ufw status               # verify both rules appear
```

Expected output:
```
Status: active
To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
3000/tcp                   ALLOW       Anywhere
```

### 2.5 Open port 3000 on GCP firewall

UFW controls the OS-level firewall. GCP has its own network firewall on top. Open port 3000 there too:

```bash
# Create a firewall rule (run from your local machine, not the VM)
gcloud compute firewall-rules create allow-langfuse-3000 \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:3000 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=langfuse \
  --description="Allow Langfuse web UI on port 3000"

# Apply the tag to your VM
gcloud compute instances add-tags dat-tran-vm \
  --tags=langfuse \
  --zone=us-central1-a
```

Verify the SSH rule was not touched:

```bash
gcloud compute firewall-rules list --filter="name~ssh"
```

---

## 3. GitHub Actions Setup

### 3.1 Repository secrets (`Settings → Secrets and variables → Actions`)

| Secret name | Value |
|---|---|
| `GCP_SSH_PRIVATE_KEY` | Private key the CI runner uses to SSH into the VM |
| `GCP_VM_HOST` | External IP of the VM |
| `DATABASE_URL` | CockroachDB connection string |
| `NEXTAUTH_SECRET` | Random secret for NextAuth session signing |
| `SALT` | Random salt for password hashing |
| `ENCRYPTION_KEY` | 64-char hex key for data encryption |
| `CLICKHOUSE_PASSWORD` | ClickHouse DB password |
| `UPSTASH_REDIS_REST_TOKEN` | Upstash Redis auth token |
| `LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY` | GCS HMAC secret key |
| `DUCKDNS_TOKEN` | DuckDNS token (only needed for DuckDNS workflow) |

### 3.2 Repository variables (`Settings → Secrets and variables → Actions → Variables`)

| Variable name | Value |
|---|---|
| `UPSTASH_REDIS_HOST` | Upstash Redis hostname |
| `REDIS_PORT` | `6379` |
| `CLICKHOUSE_USER` | `default` |
| `LANGFUSE_S3_EVENT_UPLOAD_BUCKET` | GCS bucket name |
| `LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT` | `https://storage.googleapis.com` |
| `LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID` | GCS HMAC access key ID |
| `DUCKDNS_SUBDOMAIN` | Your DuckDNS subdomain (only for DuckDNS workflow) |

### 3.3 Environment

Both workflows use the GitHub environment `langfuse_dep`. Create it under `Settings → Environments` if it doesn't exist.

---

## 4. Deployment

### 4.1 Deploy Langfuse (automatic)

Push to `main` — the `Deploy Langfuse to GCP VM` workflow triggers automatically.

What it does:
1. SSH into the VM using `GCP_SSH_PRIVATE_KEY`
2. Downloads `scripts/deploy-langfuse.sh` from the repo onto the VM
3. Runs the script, which:
   - Creates Docker network `langfuse-net`
   - Starts ClickHouse (skips if already running)
   - Pulls and restarts `langfuse-web` on port `3000`
   - Pulls and restarts `langfuse-worker`

Access the UI at: `http://<VM_EXTERNAL_IP>:3000`

### 4.2 Deploy DuckDNS (manual)

Trigger manually from `Actions → Deploy DuckDNS to GCP VM → Run workflow`.

This starts a `duckdns` container that keeps the DuckDNS domain pointed at the VM's current IP.

---

## 5. Verifying the Deployment

SSH into the VM and check container status:

```bash
docker ps --filter "name=langfuse" --filter "name=clickhouse" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Check logs for a specific container:

```bash
docker logs langfuse-web   --tail 50
docker logs langfuse-worker --tail 50
docker logs clickhouse      --tail 50
```

---

## 6. Caveats and Common Mistakes

### Firewall — SSH lockout (most critical)

> **Never run `sudo ufw enable` before adding `sudo ufw allow 22/tcp`.**
>
> UFW's default policy is `deny`. Enabling it without the SSH rule blocks port 22 and
> permanently locks you out of the VM over SSH. Recovery requires GCP serial console access.

Safe order every time:
```
1. sudo ufw allow 22/tcp    ← always first
2. sudo ufw allow <port>    ← other ports
3. sudo ufw enable          ← only then
```

If you rebuild the VM and need to re-run this, repeat from step 1 — UFW rules do not persist across OS reinstalls.

### Two firewall layers on GCP

GCP has two independent firewall layers. Opening a port in UFW (OS level) is not enough — the GCP network firewall also needs a rule. Both must allow the port for traffic to reach the VM.

| Layer | Tool | Applies to |
|---|---|---|
| GCP network firewall | `gcloud compute firewall-rules` | All traffic reaching the VM |
| OS firewall | `sudo ufw` | Traffic the OS itself processes |

### SSH key must be pre-authorised on the VM

The `GCP_SSH_PRIVATE_KEY` secret is the private half of an SSH keypair. The corresponding **public key** must be in `~/.ssh/authorized_keys` on the `davestran` user on the VM before any GitHub Actions deployment will work.

If you re-create the VM, re-add the public key:

```bash
# On the VM, as davestran:
echo "<contents of secrets/gcpdeploy_key.pub>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Docker group membership

The `davestran` user must be in the `docker` group, otherwise the deploy script fails with `permission denied` when calling `docker`. After `usermod -aG docker davestran`, you must log out and back in (or run `newgrp docker`) for it to take effect.

### ClickHouse is intentionally skipped if already running

The deploy script checks if the ClickHouse container is running and skips recreation if it is. This preserves the `clickhouse-data` volume. If you need to force-recreate ClickHouse (e.g., config change), stop it manually first:

```bash
docker stop clickhouse && docker rm clickhouse
```

Then re-trigger the deployment.

### `NEXTAUTH_URL` is derived from `GCP_VM_HOST`

The workflow hard-codes `NEXTAUTH_URL=http://<GCP_VM_HOST>:3000`. If the VM's IP changes (e.g., after a stop/start on a non-static IP), update the `GCP_VM_HOST` secret and also update any DuckDNS domain by re-running the DuckDNS workflow.

### secrets/.env is not used by CI — it is a local reference only

The file `secrets/.env` holds the raw values for reference. The actual CI deployment reads from GitHub Secrets/Variables. Keep these in sync manually when rotating credentials.

### The deploy script uses `set -euo pipefail`

Any command failure aborts the script immediately. If a deployment fails mid-way (e.g., ClickHouse is running but `langfuse-web` fails to start), re-triggering the workflow is safe — ClickHouse will be skipped and only the failed containers will be recreated.
