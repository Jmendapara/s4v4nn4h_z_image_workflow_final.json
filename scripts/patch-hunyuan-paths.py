"""Append RunPod network-volume search paths to hunyuan_shared.py.

Runs once at Docker build time so the custom node always includes
/runpod-volume/models in its folder_paths search list.
"""

TARGET = "/comfyui/custom_nodes/Comfy_HunyuanImage3/hunyuan_shared.py"

PATCH = """

# --- RunPod network-volume search paths (injected by worker build) ---
try:
    _folder_paths.add_model_folder_path(HUNYUAN_FOLDER_NAME, "/runpod-volume/models")
    _folder_paths.add_model_folder_path(HUNYUAN_INSTRUCT_FOLDER_NAME, "/runpod-volume/models")
except Exception:
    pass
"""

with open(TARGET, "a") as f:
    f.write(PATCH)

print(f"Patched {TARGET} with RunPod network-volume search paths")
