# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.7.1-base

# install custom nodes into comfyui (first node with --mode remote to fetch updated cache)
RUN comfy node install seedvr2_videoupscaler@2.5.24 --mode remote

# download models into comfyui
RUN comfy model download --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_sharp_fp16.safetensors" --relative-path models/diffusion_models --filename seedvr2_ema_7b_sharp_fp16.safetensors
RUN comfy model download --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors" --relative-path models/vae --filename ema_vae_fp16.safetensors

# Download LoRA from Google Drive
RUN pip install gdown && mkdir -p /comfyui/models/loras && gdown 1bRoyYbx__RyZCMeiO_eo6p864Ej1TMnQ -O /comfyui/models/loras/z_image_turbo_s4v4nn4h_lora.safetensors

# Download Z-Image Turbo
RUN comfy model download --url "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors" --relative-path models/diffusion_models --filename z_image_turbo_bf16.safetensors

#Downlaod Realistic Snapshot Lora
RUN gdown 1YzyHBIAKGhe7VF5w6hTJrKdqdC9cq9pQ -O /comfyui/models/loras/RealisticSnapshot-Zimage-Turbov5.safetensors

# Download Qwen CLIP (into subfolder models/clip/qwen)
RUN comfy model download --url "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors" --relative-path models/clip --filename qwen_3_4b.safetensors
# Patch ComfyUI to disable weights_only restriction for PyTorch 2.6 compatibility
RUN sed -i 's/torch\.load(\([^,]*\),/torch.load(\1, weights_only=False,/g' /comfyui/comfy/model_management.py || true

# Verify patch was applied
RUN echo "=== Patch verification ===" && \
    if grep -q "weights_only=False" /comfyui/comfy/model_management.py; then \
        echo "✓ Patch successfully applied: weights_only=False found in model_management.py"; \
        grep -n "weights_only=False" /comfyui/comfy/model_management.py | head -5; \
    else \
        echo "⚠ Patch may not have been applied, checking file contents..."; \
        grep -n "torch.load" /comfyui/comfy/model_management.py | head -5; \
    fi
# Download VAE (using HuggingFace CDN for proper file resolution)
RUN comfy model download --url "https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors" --relative-path models/vae --filename ae.safetensors

# Log VAE file size and verify download
RUN echo "=== VAE File Verification ===" && \
    ls -lh /comfyui/models/vae/ae.safetensors && \
    FILESIZE=$(stat -c%s /comfyui/models/vae/ae.safetensors) && \
    echo "File size: $FILESIZE bytes" && \
    if [ $FILESIZE -lt 1000 ]; then echo "⚠️  WARNING: VAE file is suspiciously small ($FILESIZE bytes)"; cat /comfyui/models/vae/ae.safetensors; fi


# copy all input data (like images or videos) into comfyui (uncomment and adjust if needed)
# COPY input/ /comfyui/input/

# Install RunPod SDK
RUN pip install runpod

# Copy the RunPod handler
COPY handler.py /comfyui/handler.py

# Copy test input to override default (must be at root for RunPod to find it)
COPY test_input.json /test_input.json

# Set the handler as the entrypoint
ENV HANDLER_PATH=/comfyui/handler.py