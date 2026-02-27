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
#   export MODEL_TYPE="hunyuan-instruct-nf4"   # or hunyuan-instruct-int8, z-image-turbo, base, etc.
#   bash build-on-pod.sh
#
# Prerequisites:
#   - A RunPod GPU pod with the "RunPod Pytorch" template (or any template
#     that has Docker pre-installed, or use a Docker-in-Docker template).
#   - At least 240 GB disk for hunyuan-instruct-nf4, 300 GB for hunyuan-instruct-int8, 80 GB for base.
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
    if ! systemctl start docker 2>/dev/null; then
        dockerd &>/dev/null &
        sleep 5
    fi
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
    --no-cache
    --build-arg "MODEL_TYPE=${MODEL_TYPE}"
    --build-arg "COMFYUI_VERSION=${COMFYUI_VERSION}"
)

# CUDA version selection for Hunyuan models.
# Default: CUDA 12.6 (works with RunPod driver >= 560.x, proven stable).
# Override: set CUDA_LEVEL=12.8 for Blackwell GPUs (sm_120, needs driver >= 570.x).
CUDA_LEVEL="${CUDA_LEVEL:-12.6}"

case "${MODEL_TYPE}" in
    hunyuan-instruct-nf4|hunyuan-instruct-int8)
        if [ "${CUDA_LEVEL}" = "12.8" ]; then
            BUILD_ARGS+=(
                --build-arg "BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
                --build-arg "CUDA_VERSION_FOR_COMFY=12.8"
                --build-arg "ENABLE_PYTORCH_UPGRADE=true"
                --build-arg "PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu128"
            )
            echo "       Using CUDA 12.8 base + PyTorch cu128 (Blackwell, needs driver >= 570)"
        else
            BUILD_ARGS+=(
                --build-arg "BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
                --build-arg "CUDA_VERSION_FOR_COMFY=12.6"
            )
            echo "       Using CUDA 12.6 base (default, works with driver >= 560)"
        fi
        ;;
esac

if [ -n "${HUGGINGFACE_ACCESS_TOKEN}" ]; then
    BUILD_ARGS+=(--build-arg "HUGGINGFACE_ACCESS_TOKEN=${HUGGINGFACE_ACCESS_TOKEN}")
fi

# Free disk: remove old images, containers, and build cache before building
docker system prune -af --volumes 2>/dev/null || true
docker builder prune -af 2>/dev/null || true
echo "       Available disk: $(df -h /var/lib/docker 2>/dev/null | tail -1 | awk '{print $4}') free"

# Use the docker-container buildx driver for large images (INT8 ~83GB).
# The default "docker" driver uses the local containerd snapshotter which can
# fail with "Lchown ... no such file or directory" on images >50GB.
BUILDER_NAME="large-image-builder"
if ! docker buildx inspect "${BUILDER_NAME}" &>/dev/null; then
    echo "       Creating buildx builder '${BUILDER_NAME}' (docker-container driver)..."
    docker buildx create --name "${BUILDER_NAME}" --driver docker-container --use
else
    docker buildx use "${BUILDER_NAME}"
fi

docker buildx build "${BUILD_ARGS[@]}" --load -t "${IMAGE_TAG}" .

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
