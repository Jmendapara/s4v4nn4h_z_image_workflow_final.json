#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

# Symlink Hunyuan Instruct model directories from the network volume into
# ComfyUI's default models dir so the HunyuanInstructLoader scanner finds them.
# Also creates a version-stripped alias (e.g. -NF4-v2 → -NF4) to match the
# hardcoded fallback names in the custom node validation list.
if [ -d "/runpod-volume/models" ]; then
    for dir in /runpod-volume/models/HunyuanImage-3.0-*; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        target="/comfyui/models/${name}"
        if [ ! -e "$target" ]; then
            ln -s "$dir" "$target"
            echo "worker-comfyui: Linked ${name} into ComfyUI models"
        fi
        # Create alias without version suffix (e.g. -NF4-v2 → -NF4)
        stripped="$(echo "$name" | sed 's/-v[0-9]*$//')"
        if [ "$stripped" != "$name" ]; then
            alias_target="/comfyui/models/${stripped}"
            if [ ! -e "$alias_target" ]; then
                ln -s "$dir" "$alias_target"
                echo "worker-comfyui: Linked ${stripped} (alias) into ComfyUI models"
            fi
        fi
    done
fi

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi