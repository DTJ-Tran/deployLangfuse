"""
Modal script to build and push custom Phoenix Docker image to GCP Artifact Registry.

Uses Kaniko (daemonless Docker builder) inside Modal — mirrors the PILOT_PROJECT
pattern (gcr.io/kaniko-project/executor:debug COPY --from, add_local_dir baked in).

Modal secret required (create at modal.com/secrets):
  Name : gcp-phoenix-builder
  Keys : GCP_SERVICE_ACCOUNT_KEY  (full JSON of the GCP service account key)

Usage:
    modal run scripts/build-phoenix-image.py \\
        --registry us-central1-docker.pkg.dev \\
        --image-name <PROJECT_ID>/phoenix/phoenix \\
        --tag latest \\
        --push
"""

import json
import os
from pathlib import Path
import subprocess

import modal

# =============================================================================
# Configuration
# =============================================================================
AR_HOST = "us-central1-docker.pkg.dev"
APP_NAME = "phoenix-image-builder"

# =============================================================================
# Modal Image Definition
# =============================================================================
builder_image = (
    modal.Image.debian_slim()
    .apt_install("ca-certificates")
    # Copy Kaniko executor directly from its official image layer — no wget needed
    .dockerfile_commands(
        [
            "COPY --from=gcr.io/kaniko-project/executor:debug /kaniko/executor /usr/local/bin/kaniko"
        ]
    )
    # Bake the Dockerfile + build context into the image at Modal build time
    .add_local_dir(
        "docker/phoenix",
        remote_path="/workspace",
    )
)

app = modal.App(APP_NAME, image=builder_image)

# =============================================================================
# Build and Push Function
# =============================================================================
@app.function(
    timeout=900,
    cpu=4,
    memory=8192,
    secrets=[modal.Secret.from_name("gcp-phoenix-builder")],
)
def build_and_push(
    registry: str = AR_HOST,
    image_name: str = "phoenix/phoenix",
    tag: str = "latest",
    push: bool = True,
    platform: str = "linux/amd64",
) -> dict:
    workspace_root = Path("/workspace")
    dockerfile_path = workspace_root / "Dockerfile"
    full_image = f"{registry}/{image_name}:{tag}"

    print(f"Building {full_image} for {platform}")

    # --- Artifact Registry auth ---
    docker_config_dir = None
    if push:
        sa_key_json = os.environ["GCP_SERVICE_ACCOUNT_KEY"]
        config = {
            "auths": {
                registry: {
                    "username": "_json_key",
                    "password": sa_key_json,
                }
            }
        }
        docker_config_dir = workspace_root / ".kaniko"
        docker_config_dir.mkdir(exist_ok=True)
        (docker_config_dir / "config.json").write_text(json.dumps(config))
        print(f"Artifact Registry auth configured for {registry}")

    # --- Inspect workspace (debug) ---
    print("\n=== Workspace contents ===")
    result = subprocess.run(["ls", "-la", str(workspace_root)], capture_output=True, text=True)
    print(result.stdout)
    print("==========================\n")

    # --- Run Kaniko ---
    kaniko_cmd = [
        "/usr/local/bin/kaniko",
        "--context", str(workspace_root),
        "--dockerfile", str(dockerfile_path),
        "--destination", full_image,
        "--custom-platform", platform,
        "--verbosity", "info",
    ]

    current_env = os.environ.copy()
    if docker_config_dir:
        current_env["DOCKER_CONFIG"] = str(docker_config_dir)

    print(f"Running Kaniko: {' '.join(kaniko_cmd)}")
    result = subprocess.run(kaniko_cmd, capture_output=True, text=True, env=current_env)

    print(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(f"Kaniko build failed:\n{result.stderr}")

    print(f"Push complete: {full_image}")
    return {"image": full_image}


# =============================================================================
# CLI Entry Point
# =============================================================================
@app.local_entrypoint()
def main(
    registry: str = AR_HOST,
    image_name: str = "",
    tag: str = "latest",
    push: bool = True,
    platform: str = "linux/amd64",
):
    project = os.environ.get("GCP_PROJECT_ID", "")
    if not image_name:
        if not project:
            raise SystemExit("ERROR: set GCP_PROJECT_ID env var or pass --image-name")
        image_name = f"{project}/phoenix/phoenix"

    full_image = f"{registry}/{image_name}:{tag}"

    print("=" * 60)
    print("Phoenix Docker Build on Modal (Kaniko)")
    print("=" * 60)
    print(f"Registry : {registry}")
    print(f"Image    : {image_name}")
    print(f"Tag      : {tag}")
    print(f"Push     : {push}")
    print(f"Platform : {platform}")
    print("=" * 60)

    result = build_and_push.remote(
        registry=registry,
        image_name=image_name,
        tag=tag,
        push=push,
        platform=platform,
    )

    print("\n" + "=" * 60)
    print("BUILD COMPLETE")
    print("=" * 60)
    print(f"Image: {result['image']}")
    print("=" * 60)
    print(f"::set-output name=image::{result['image']}")
