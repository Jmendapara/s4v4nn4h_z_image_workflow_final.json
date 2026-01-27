# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.5.1-base

# install custom nodes into comfyui (first node with --mode remote to fetch updated cache)
RUN comfy node install --exit-on-fail seedvr2_videoupscaler@2.5.24 --mode remote

# download models into comfyui
RUN comfy model download --url https://huggingface.co/numz/SeedVR2_comfyUI/blob/main/seedvr2_ema_7b_sharp_fp16.safetensors --relative-path models/diffusion_models --filename seedvr2_ema_7b_sharp_fp16.safetensors
RUN comfy model download --url https://huggingface.co/numz/SeedVR2_comfyUI/blob/main/ema_vae_fp16.safetensors --relative-path models/vae --filename ema_vae_fp16.safetensors
# Download LoRA from Google Drive
RUN comfy model download --url https://drive.google.com/uc?export=download&id=1bRoyYbx__RyZCMeiO_eo6p864Ej1TMnQ --relative-path models/loras --filename z_image_turbo_s4v4nn4h_lora.safetensors

# Download Z-Image Turbo
RUN comfy model download --url https://huggingface.co/Comfy-Org/z_image_turbo/blob/main/split_files/diffusion_models/z_image_turbo_bf16.safetensors --relative-path models/diffusion_models --filename z_image_turbo_bf16.safetensors

# Download Qwen CLIP (into subfolder models/clip/qwen)
RUN comfy model download --url https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/blob/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors --relative-path models/clip/qwen --filename qwen_2.5_vl_7b_fp8_scaled.safetensors

# Download VAE
RUN comfy model download --url https://huggingface.co/Comfy-Org/z_image_turbo/blob/main/split_files/vae/ae.safetensors --relative-path models/vae --filename ae.safetensors


# copy all input data (like images or videos) into comfyui (uncomment and adjust if needed)
# COPY input/ /comfyui/input/

# Install RunPod SDK
RUN pip install runpod

# Copy the RunPod handler
COPY handler.py /comfyui/handler.py

# Set the handler as the entrypoint
ENV HANDLER_PATH=/comfyui/handler.py