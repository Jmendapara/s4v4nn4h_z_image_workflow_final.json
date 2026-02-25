#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Build Docker image on a RunPod GPU Pod and push to Docker Hub.
#
# Usage (run inside a RunPod pod via SSH or web terminal):
#
#   export DOCKERHUB_USERNAME="your-dockerhub-user"
#   export DOCKERHUB_TOKEN="your-dockerhub-access-token"
#   export IMAGE_TAG="your-user/worker-comfyui:latest-hunyuan-instruct-nf4"
#   export MODEL_TYPE="hunyuan-instruct-nf4"   # or z-image-turbo, base, etc.
#   bash build-on-pod.sh
#
# Prerequisites:
#   - A RunPod GPU pod with the "RunPod Pytorch" template (or any template
#     that has Docker pre-installed, or use a Docker-in-Docker template).
#   - At least 80 GB container disk (for hunyuan-instruct-nf4; 50 GB for base).
#   - Git and internet access (default on RunPod pods).
# =============================================================================

REPO_URL="${REPO_URL:-https://github.com/Jmendapara/s4v4nn4h_z_image_workflow_final.json.git}"
BRANCH="${BRANCH:-main}"
MODEL_TYPE="${MODEL_TYPE:-hunyuan-instruct-nf4}"
COMFYUI_VERSION="${COMFYUI_VERSION:-v0.14.2}"
HUGGINGFACE_ACCESS_TOKEN="${HUGGINGFACE_ACCESS_TOKEN:-}"

# Docker Hub credentials
: "${DOCKERHUB_USERNAME:?Set DOCKERHUB_USERNAME}"
: "${DOCKERHUB_TOKEN:?Set DOCKERHUB_TOKEN}"
: "${IMAGE_TAG:?Set IMAGE_TAG (e.g. yourdockerhubuser/worker-comfyui:latest-hunyuan-instruct-nf4)}"

echo "============================================="
echo " RunPod Docker Image Builder"
echo "============================================="
echo "  Repo:          ${REPO_URL}"
echo "  Branch:        ${BRANCH}"
echo "  Model type:    ${MODEL_TYPE}"
echo "  ComfyUI ver:   ${COMFYUI_VERSION}"
echo "  Image tag:     ${IMAGE_TAG}"
echo "  HF token:      ${HUGGINGFACE_ACCESS_TOKEN:+(set)}"
echo "============================================="

# ---- Step 1: Ensure Docker (with BuildKit/buildx) is installed and running ----
if ! command -v docker &>/dev/null || ! docker buildx version &>/dev/null 2>&1; then
    echo "[1/5] Installing Docker via get.docker.com..."
    curl -fsSL https://get.docker.com | sh
    echo "[1/5] Docker installed."
else
    echo "[1/5] Docker already available: $(docker --version)"
fi

if ! docker info &>/dev/null 2>&1; then
    echo "[1/5] Starting Docker daemon..."
    systemctl start docker 2>/dev/null || (dockerd &>/dev/null &  && sleep 5)
fi
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running."; exit 1; }

# ---- Step 2: Log into Docker Hub ----
echo "[2/5] Logging into Docker Hub..."
echo "${DOCKERHUB_TOKEN}" | docker login --username "${DOCKERHUB_USERNAME}" --password-stdin
echo "[2/5] Logged in."

# ---- Step 3: Clone the repo ----
WORK_DIR="/tmp/build-workspace"
if [ -d "${WORK_DIR}" ]; then
    echo "[3/5] Cleaning previous build workspace..."
    rm -rf "${WORK_DIR}"
fi
echo "[3/5] Cloning repo (branch: ${BRANCH})..."
git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${WORK_DIR}"
cd "${WORK_DIR}"
echo "[3/5] Repo cloned."

# ---- Step 4: Build the Docker image ----
echo "[4/5] Building Docker image (this will take a while)..."
echo "       MODEL_TYPE=${MODEL_TYPE}, target=final"

BUILD_ARGS=(
    --platform linux/amd64
    --target final
    --build-arg "MODEL_TYPE=${MODEL_TYPE}"
    --build-arg "COMFYUI_VERSION=${COMFYUI_VERSION}"
)
if [ -n "${HUGGINGFACE_ACCESS_TOKEN}" ]; then
    BUILD_ARGS+=(--build-arg "HUGGINGFACE_ACCESS_TOKEN=${HUGGINGFACE_ACCESS_TOKEN}")
fi

DOCKER_BUILDKIT=1 docker build "${BUILD_ARGS[@]}" -t "${IMAGE_TAG}" .

echo "[4/5] Build complete!"
echo "       Image size: $(docker images "${IMAGE_TAG}" --format '{{.Size}}')"

# ---- Step 5: Push to Docker Hub ----
echo "[5/5] Pushing ${IMAGE_TAG} to Docker Hub..."
docker push "${IMAGE_TAG}"
echo "[5/5] Push complete!"

echo ""
echo "============================================="
echo " SUCCESS"
echo "============================================="
echo " Image pushed: ${IMAGE_TAG}"
echo ""
echo " Next steps:"
echo "   1. Go to https://www.runpod.io/console/serverless"
echo "   2. Create a new endpoint with container image:"
echo "      ${IMAGE_TAG}"
echo "   3. Pick a GPU (A100 80GB recommended for hunyuan)"
echo "   4. Set Min Workers=0, Max Workers=1"
echo "   5. Destroy this pod to stop charges!"
echo "============================================="
