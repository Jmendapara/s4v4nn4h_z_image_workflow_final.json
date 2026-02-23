#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

# Symlink Hunyuan model directories from the network volume so the
# HunyuanInstructLoader can find them. We link into two locations:
#   /comfyui/models/<name>  — for the scanner (searches models_dir)
#   /comfyui/<name>         — fallback: bare name resolves from cwd /comfyui
if [ -d "/runpod-volume/models" ]; then
    for dir in /runpod-volume/models/HunyuanImage-3.0-*; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"

        for prefix in /comfyui/models /comfyui; do
            target="${prefix}/${name}"
            if [ ! -e "$target" ]; then
                ln -s "$dir" "$target"
                echo "worker-comfyui: Linked ${name} -> ${target}"
            fi
            # Also create alias without version suffix (-v2 → stripped)
            stripped="$(echo "$name" | sed 's/-v[0-9]*$//')"
            if [ "$stripped" != "$name" ]; then
                alias="${prefix}/${stripped}"
                if [ ! -e "$alias" ]; then
                    ln -s "$dir" "$alias"
                    echo "worker-comfyui: Linked ${stripped} (alias) -> ${alias}"
                fi
            fi
        done
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