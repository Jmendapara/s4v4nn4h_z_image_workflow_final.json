#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Setup ComfyUI + HunyuanImage 3.0 NF4 on a RunPod GPU Pod
#
# Usage:
#   1. Create a RunPod GPU Pod (A100 80GB, 100GB container disk, 60GB volume)
#   2. Open the web terminal or SSH in
#   3. Run:
#        curl -fsSL https://raw.githubusercontent.com/Jmendapara/s4v4nn4h_z_image_workflow_final.json/main/scripts/setup-pod.sh | bash
#
#   Or if already cloned:
#        bash scripts/setup-pod.sh
#
# The script installs ComfyUI, the Comfy_HunyuanImage3 nodes, downloads the
# NF4 model to the persistent volume, and starts ComfyUI on port 8188.
# =============================================================================

WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="${WORKSPACE}/ComfyUI"
MODEL_DIR="${COMFYUI_DIR}/models/HunyuanImage-3.0-Instruct-Distil-NF4"

echo "============================================="
echo " ComfyUI + HunyuanImage 3.0 NF4 Pod Setup"
echo "============================================="
echo "  Workspace:  ${WORKSPACE}"
echo "  ComfyUI:    ${COMFYUI_DIR}"
echo "  Model dir:  ${MODEL_DIR}"
echo "============================================="

# ---- Step 1: Install ComfyUI ----
if [ -d "${COMFYUI_DIR}/main.py" ] || [ -f "${COMFYUI_DIR}/main.py" ]; then
    echo "[1/5] ComfyUI already installed at ${COMFYUI_DIR}"
else
    echo "[1/5] Installing ComfyUI..."
    pip install comfy-cli
    /usr/bin/yes | comfy --workspace "${COMFYUI_DIR}" install --nvidia
    echo "[1/5] ComfyUI installed."
fi

# ---- Step 2: Install Comfy_HunyuanImage3 custom nodes ----
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes/Comfy_HunyuanImage3"
if [ -d "${CUSTOM_NODES_DIR}" ]; then
    echo "[2/5] Comfy_HunyuanImage3 already cloned, pulling latest..."
    cd "${CUSTOM_NODES_DIR}" && git pull && cd -
else
    echo "[2/5] Cloning Comfy_HunyuanImage3..."
    git clone https://github.com/EricRollei/Comfy_HunyuanImage3 "${CUSTOM_NODES_DIR}"
fi

echo "[2/5] Installing node requirements..."
pip install -r "${CUSTOM_NODES_DIR}/requirements.txt"

# ---- Step 3: Ensure correct dependency versions ----
echo "[3/5] Upgrading key dependencies..."
pip install \
    "diffusers>=0.31.0" \
    "transformers>=4.47.0" \
    "bitsandbytes>=0.48.2" \
    "accelerate>=1.2.1" \
    "huggingface_hub[hf_xet]"

# ---- Step 4: Download the model ----
if [ -d "${MODEL_DIR}" ] && [ "$(ls -A "${MODEL_DIR}" 2>/dev/null)" ]; then
    echo "[4/5] Model already downloaded at ${MODEL_DIR}"
else
    echo "[4/5] Downloading HunyuanImage-3.0-Instruct-Distil-NF4-v2 (~48 GB)..."
    echo "       This will take 10-30 minutes depending on bandwidth."
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    'EricRollei/HunyuanImage-3.0-Instruct-Distil-NF4-v2',
    local_dir='${MODEL_DIR}'
)
"
    echo "[4/5] Model downloaded."
fi

# Create the v2 alias symlink if it doesn't exist
V2_LINK="${COMFYUI_DIR}/models/HunyuanImage-3.0-Instruct-Distil-NF4-v2"
if [ ! -e "${V2_LINK}" ]; then
    ln -s "${MODEL_DIR}" "${V2_LINK}"
    echo "[4/5] Created v2 symlink alias."
fi

# ---- Step 5: Print versions and start ComfyUI ----
echo ""
echo "============================================="
echo " Setup Complete — Package Versions"
echo "============================================="
python3 -c "
import torch, bitsandbytes, transformers, diffusers, accelerate
print(f'  PyTorch:        {torch.__version__}')
print(f'  CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'  GPU:            {torch.cuda.get_device_name(0)}')
    print(f'  VRAM:           {torch.cuda.get_device_properties(0).total_mem / 1024**3:.1f} GB')
print(f'  bitsandbytes:   {bitsandbytes.__version__}')
print(f'  transformers:   {transformers.__version__}')
print(f'  diffusers:      {diffusers.__version__}')
print(f'  accelerate:     {accelerate.__version__}')
"
echo "============================================="
echo ""
echo " Starting ComfyUI on port 8188..."
echo " Open the RunPod Connect button and click"
echo " the HTTP 8188 link to access the web UI."
echo ""
echo " To access via URL:"
echo "   https://{POD_ID}-8188.proxy.runpod.net/"
echo ""
echo "============================================="

cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
