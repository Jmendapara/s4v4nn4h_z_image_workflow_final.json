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