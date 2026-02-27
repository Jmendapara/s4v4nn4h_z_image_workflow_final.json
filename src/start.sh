#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

# ---------- Diagnostics: network-volume detection ----------
echo "worker-comfyui: Detecting network volume..."
echo "  /runpod-volume exists: $([ -d /runpod-volume ] && echo YES || echo NO)"
echo "  /runpod-volume/models exists: $([ -d /runpod-volume/models ] && echo YES || echo NO)"
echo "  /workspace exists: $([ -d /workspace ] && echo YES || echo NO)"
echo "  /workspace/models exists: $([ -d /workspace/models ] && echo YES || echo NO)"
ls -la /runpod-volume/models/ 2>/dev/null || echo "  (cannot list /runpod-volume/models/)"
ls -la /workspace/models/ 2>/dev/null || echo "  (cannot list /workspace/models/)"

# ---------- Symlink Hunyuan models into ComfyUI search paths ----------
# Check both possible RunPod volume mount points.
HUNYUAN_FOUND=0
for vol_base in /runpod-volume /workspace; do
    for dir in "${vol_base}"/models/HunyuanImage-3.0-*; do
        [ -d "$dir" ] || continue
        HUNYUAN_FOUND=1
        name="$(basename "$dir")"
        echo "worker-comfyui: Found model ${name} at ${dir}"

        for prefix in /comfyui/models /comfyui; do
            target="${prefix}/${name}"
            if [ ! -e "$target" ]; then
                ln -s "$dir" "$target"
                echo "worker-comfyui: Linked -> ${target}"
            fi
            stripped="$(echo "$name" | sed 's/-v[0-9]*$//')"
            if [ "$stripped" != "$name" ] && [ ! -e "${prefix}/${stripped}" ]; then
                ln -s "$dir" "${prefix}/${stripped}"
                echo "worker-comfyui: Linked alias -> ${prefix}/${stripped}"
            fi
        done
    done
done

if [ "$HUNYUAN_FOUND" -eq 0 ]; then
    echo "worker-comfyui: WARNING — no HunyuanImage-3.0-* dirs found on any volume!"
fi

echo "worker-comfyui: /comfyui/models/ listing:"
ls -la /comfyui/models/ 2>/dev/null || echo "  (empty or missing)"

# ---------- Pre-launch diagnostics ----------
echo "worker-comfyui: System info before launch:"
echo "  GPU(s):"
nvidia-smi --query-gpu=gpu_name,memory.total,driver_version,compute_cap --format=csv,noheader 2>/dev/null \
    || echo "  (nvidia-smi not available)"
echo "  CUDA runtime version:"
python -c "import torch; print(f'  PyTorch {torch.__version__}, CUDA {torch.version.cuda}')" 2>/dev/null \
    || echo "  (torch not importable)"
echo "  Key package versions:"
python -c "
import importlib, sys
for pkg in ['torch', 'bitsandbytes', 'diffusers', 'transformers', 'accelerate', 'comfy_api']:
    try:
        m = importlib.import_module(pkg)
        v = getattr(m, '__version__', '?')
        print(f'    {pkg}=={v}')
    except ImportError:
        print(f'    {pkg}: not installed')
" 2>/dev/null || echo "  (could not list packages)"
echo "  System RAM:"
free -h 2>/dev/null | head -2 || echo "  (free not available)"
echo ""

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
EXTRA_PATHS="--extra-model-paths-config /comfyui/extra_model_paths.yaml"

COMFY_LOG="/var/log/comfyui.log"

# Launch ComfyUI with output teed to a log file so crash messages survive.
# The handler reads this log when ComfyUI dies unexpectedly.
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen ${EXTRA_PATHS} --verbose "${COMFY_LOG_LEVEL}" --log-stdout 2>&1 | tee "${COMFY_LOG}" &
    COMFY_PID=$!

    echo "worker-comfyui: ComfyUI PID=${COMFY_PID}, log=${COMFY_LOG}"
    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata ${EXTRA_PATHS} --verbose "${COMFY_LOG_LEVEL}" --log-stdout 2>&1 | tee "${COMFY_LOG}" &
    COMFY_PID=$!

    echo "worker-comfyui: ComfyUI PID=${COMFY_PID}, log=${COMFY_LOG}"
    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi