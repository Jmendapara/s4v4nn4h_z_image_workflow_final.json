# HunyuanImage 3.0 — Serverless ComfyUI Worker

> [ComfyUI](https://github.com/comfyanonymous/ComfyUI) + [HunyuanImage 3.0 Instruct Distil NF4](https://huggingface.co/EricRollei/HunyuanImage-3.0-Instruct-Distil-NF4-v2) as a serverless API on [RunPod](https://www.runpod.io/)

---

## Table of Contents

- [Overview](#overview)
- [Model Details](#model-details)
- [Step 1: Build the Docker Image](#step-1-build-the-docker-image)
- [Step 2: Push to a Container Registry](#step-2-push-to-a-container-registry)
- [Step 3: Deploy on RunPod](#step-3-deploy-on-runpod)
- [Step 4: Test Your Endpoint](#step-4-test-your-endpoint)
- [API Specification](#api-specification)
- [Environment Variables](#environment-variables)
- [Cost Estimates](#cost-estimates)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project packages ComfyUI with the HunyuanImage 3.0 Instruct Distil NF4 model baked into a Docker image. The image runs as a serverless worker on RunPod — you send a workflow via API and receive generated/edited images back as base64 strings or S3 URLs.

The model is baked directly into the Docker image (~55 GB total). No network volume is required.

## Model Details

| Property | Value |
|---|---|
| Model | [HunyuanImage 3.0 Instruct Distil NF4 v2](https://huggingface.co/EricRollei/HunyuanImage-3.0-Instruct-Distil-NF4-v2) |
| Architecture | Mixture-of-Experts Diffusion Transformer |
| Parameters | 80B total, 13B active per token |
| Quantization | NF4 (4-bit) via bitsandbytes |
| Diffusion Steps | 8 (CFG-distilled) |
| Capabilities | Text-to-image, image editing, multi-image fusion |
| On-disk Size | ~48 GB |
| VRAM Required | ~41–49 GB (A100 80GB recommended) |
| ComfyUI Nodes | [Comfy_HunyuanImage3](https://github.com/EricRollei/Comfy_HunyuanImage3) |

---

## Step 1: Build the Docker Image

The image is ~55 GB and must be built on a remote server with enough disk space. A GPU is **not** needed for building.

### 1.1 Create a Cloud Server

Use a cheap VPS from [Hetzner Cloud](https://console.hetzner.cloud/) or any provider.

| Setting | Value |
|---|---|
| Provider | Hetzner Cloud (or any VPS) |
| OS | Ubuntu 24.04 |
| Server type | CPX51 or larger (8 vCPU, 16 GB RAM, 240 GB disk) |
| Disk | 240 GB minimum for `hunyuan-instruct-nf4` |
| Estimated cost | ~$0.04/hour |

> **Important:** The CPX41 (160 GB disk) may not be enough for building this image. Docker needs space for intermediate build layers in addition to the final image. Use 240 GB+ to be safe.

### 1.2 SSH into the Server

```bash
ssh root@YOUR_SERVER_IP
```

### 1.3 Install Docker

```bash
curl -fsSL https://get.docker.com | sh
systemctl start docker
```

### 1.4 Set Environment Variables

```bash
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_TOKEN="dckr_pat_your_access_token"
export IMAGE_TAG="your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4"
export MODEL_TYPE="hunyuan-instruct-nf4"
```

### 1.5 Run the Build Script

```bash
cd /tmp && curl -fsSL https://raw.githubusercontent.com/Jmendapara/s4v4nn4h_z_image_workflow_final.json/main/scripts/build-on-pod.sh | bash
```

> **Note:** Always run from `/tmp` (or any directory outside the build workspace). The script deletes and re-creates `/tmp/build-workspace`, which fails if your shell is currently inside that directory.

This script:
1. Installs Docker if needed
2. Logs into Docker Hub
3. Clones this repo
4. Builds the Docker image with PyTorch 2.8+, bitsandbytes, and the HunyuanImage 3.0 NF4 model baked in
5. Pushes the image to Docker Hub

Expect **60–90 minutes** for the full build + push.

### 1.6 Delete the Server

Once the push completes, **delete the server immediately** to stop charges.

---

## Step 2: Push to a Container Registry

The build script pushes to Docker Hub automatically. If the push fails (502 errors are common for 50+ GB layers), retry:

```bash
docker push your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4
```

Docker skips layers that already uploaded successfully and only retries the failed ones.

### Alternative: Push to GitHub Container Registry

GHCR handles large layers more reliably than Docker Hub. To use it instead:

```bash
echo YOUR_GITHUB_PAT | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
docker tag your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4 \
  ghcr.io/YOUR_GITHUB_USERNAME/worker-comfyui:latest-hunyuan-instruct-nf4
docker push ghcr.io/YOUR_GITHUB_USERNAME/worker-comfyui:latest-hunyuan-instruct-nf4
```

RunPod accepts images from any public container registry — Docker Hub, GHCR, Amazon ECR, etc.

---

## Step 3: Deploy on RunPod

### 3.1 Create a RunPod Account

Sign up at [runpod.io](https://www.runpod.io/) and add credits.

### 3.2 Get a RunPod API Key

Go to [Settings > API Keys](https://www.runpod.io/console/serverless/user/settings) and generate a key. Save it — you'll need it to call the endpoint.

### 3.3 Create a Serverless Endpoint

1. Go to [RunPod Serverless Console](https://www.runpod.io/console/serverless)
2. Click **+ New Endpoint**
3. Configure with these settings:

| Setting | Value | Notes |
|---|---|---|
| **Container Image** | `your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4` | Or `ghcr.io/...` if using GHCR |
| **GPU** | **A100 80GB** | Required — 48 GB GPUs will OOM |
| **Min Workers** | `0` | Scales to zero when idle (no cost) |
| **Max Workers** | `1` | Increase for higher throughput |
| **Container Disk** | `20 GB` | Scratch space only; model is in the image |
| **Idle Timeout** | `5` seconds | How long a warm worker waits before shutting down |
| **FlashBoot** | Enabled (if available) | Speeds up cold starts |

4. **Do NOT set** a start command — the image uses its built-in `/start.sh`
5. **Do NOT attach** a network volume — the model is baked into the image
6. Click **Create**
7. Note your **Endpoint ID** from the endpoint overview page

### 3.4 Environment Variables (Optional)

No environment variables are required for basic operation. The endpoint works out of the box.

If you need optional features, add these in the RunPod endpoint template under **Environment Variables**:

| Variable | Required | Description |
|---|---|---|
| `BUCKET_ENDPOINT_URL` | No | S3 bucket URL to upload images instead of returning base64 |
| `BUCKET_ACCESS_KEY_ID` | No | AWS access key for S3 upload |
| `BUCKET_SECRET_ACCESS_KEY` | No | AWS secret key for S3 upload |
| `COMFY_ORG_API_KEY` | No | Comfy.org API key for API Nodes |
| `COMFY_LOG_LEVEL` | No | Logging verbosity: `DEBUG`, `INFO`, `WARNING`, `ERROR` (default: `DEBUG`) |
| `REFRESH_WORKER` | No | Set `true` to restart the worker after each job for a clean state |

---

## Step 4: Test Your Endpoint

### 4.1 First Request (Cold Start)

The first request after the endpoint is created (or after it scales to zero) triggers a **cold start**:
- RunPod pulls the ~55 GB image (first time only — cached after that)
- ComfyUI starts and loads the model into GPU VRAM

The first-ever cold start takes **10–30 minutes** (image pull). Subsequent cold starts take **2–5 minutes** (model loading only, image is cached).

### 4.2 Text-to-Image Request

Send a workflow to the `/runsync` endpoint:

```bash
curl -X POST "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": {
        "1": {
          "inputs": {
            "model_name": "HunyuanImage-3.0-Instruct-Distil-NF4",
            "force_reload": false,
            "attention_impl": "sdpa",
            "moe_impl": "eager",
            "vram_reserve_gb": 30,
            "blocks_to_swap": 0
          },
          "class_type": "HunyuanInstructLoader",
          "_meta": { "title": "Hunyuan Instruct Loader" }
        },
        "3": {
          "inputs": {
            "model": ["1", 0],
            "prompt": "A golden retriever sitting on a beach at sunset",
            "bot_task": "image",
            "seed": 42,
            "system_prompt": "dynamic",
            "resolution": "1024x1024 (1:1 Square)",
            "steps": -1,
            "guidance_scale": -1,
            "flow_shift": 2.8,
            "max_new_tokens": 2048,
            "verbose": 0
          },
          "class_type": "HunyuanInstructGenerate",
          "_meta": { "title": "Hunyuan Instruct Generate" }
        },
        "4": {
          "inputs": {
            "filename_prefix": "ComfyUI",
            "images": ["3", 0]
          },
          "class_type": "SaveImage",
          "_meta": { "title": "Save Image" }
        }
      }
    }
  }'
```

### 4.3 Image Editing Request

To edit an existing image, use `HunyuanInstructImageEdit` and pass the input image as base64:

```bash
curl -X POST "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": {
        "1": {
          "inputs": {
            "model_name": "HunyuanImage-3.0-Instruct-Distil-NF4",
            "force_reload": false,
            "attention_impl": "sdpa",
            "moe_impl": "eager",
            "vram_reserve_gb": 30,
            "blocks_to_swap": 0
          },
          "class_type": "HunyuanInstructLoader",
          "_meta": { "title": "Hunyuan Instruct Loader" }
        },
        "2": {
          "inputs": {
            "image": "input_image.png",
            "upload": "image"
          },
          "class_type": "LoadImage",
          "_meta": { "title": "Load Image" }
        },
        "3": {
          "inputs": {
            "model": ["1", 0],
            "image": ["2", 0],
            "instruction": "Change the background to a sunset scene",
            "bot_task": "image",
            "seed": -1,
            "system_prompt": "dynamic",
            "align_output_size": true,
            "steps": -1,
            "guidance_scale": -1,
            "flow_shift": 2.8,
            "max_new_tokens": 2048,
            "verbose": 0
          },
          "class_type": "HunyuanInstructImageEdit",
          "_meta": { "title": "Hunyuan Instruct Image Edit" }
        },
        "4": {
          "inputs": {
            "filename_prefix": "ComfyUI",
            "images": ["3", 0]
          },
          "class_type": "SaveImage",
          "_meta": { "title": "Save Image" }
        }
      },
      "images": [
        {
          "name": "input_image.png",
          "image": "<base64 encoded image>"
        }
      ]
    }
  }'
```

Replace `<base64 encoded image>` with the actual base64-encoded image string (with or without the `data:image/png;base64,` prefix).

### 4.4 Workflow Parameters

Key parameters you can adjust in the workflow:

| Parameter | Node | Description | Options |
|---|---|---|---|
| `prompt` | HunyuanInstructGenerate | Text prompt for generation | Any text |
| `instruction` | HunyuanInstructImageEdit | The edit instruction | Any text prompt |
| `bot_task` | Generate / ImageEdit | Generation mode | `image` (fastest), `recaption` (medium), `think_recaption` (best quality) |
| `resolution` | HunyuanInstructGenerate | Output resolution | Must use exact format: `"1024x1024 (1:1 Square)"` — see full list below |
| `blocks_to_swap` | HunyuanInstructLoader | Offload transformer blocks to CPU | `0` for A100 80GB, `16`+ for 48GB GPUs |
| `vram_reserve_gb` | HunyuanInstructLoader | VRAM to keep free for inference | `30` recommended for NF4 on A100 80GB |
| `seed` | Generate / ImageEdit | Random seed | `-1` for random, or a fixed integer |
| `steps` | Generate / ImageEdit | Diffusion steps | `-1` for default (8 steps) |
| `guidance_scale` | Generate / ImageEdit | CFG scale | `-1` for default (2.5) |

### 4.5 Resolution Options

The `resolution` field requires an exact string from this list (33 model-native bucket resolutions + Auto). Using a bare value like `"1024x1024"` will fail.

**Portraits:**
`"512x2048 (1:4 Tall)"`, `"512x1920 (4:15 Tall)"`, `"576x1792 (9:28 Portrait)"`, `"576x1664 (9:26 Portrait)"`, `"640x1536 (5:12 Portrait)"`, `"640x1408 (5:11 Portrait)"`, `"704x1344 (11:21 Portrait)"`, `"704x1216 (11:19 Portrait)"`, `"768x1152 (2:3 Portrait)"`, `"768x1088 (12:17 Portrait)"`, `"832x1024 (13:16 Portrait)"`, `"832x960 (13:15 Portrait)"`, `"896x1152 (7:9 Portrait)"`, `"960x1088 (15:17 Portrait)"`

**Square:**
`"1024x1024 (1:1 Square)"`

**Landscapes:**
`"1088x960 (17:15 Landscape)"`, `"1152x896 (9:7 Landscape)"`, `"1024x832 (16:13 Landscape)"`, `"960x832 (15:13 Landscape)"`, `"1152x768 (3:2 Landscape)"`, `"1088x768 (17:12 Landscape)"`, `"1344x704 (21:11 Landscape)"`, `"1216x704 (19:11 Landscape)"`, `"1536x640 (12:5 Landscape)"`, `"1408x640 (11:5 Landscape)"`, `"1792x576 (28:9 Wide)"`, `"1664x576 (26:9 Wide)"`, `"1920x512 (15:4 Wide)"`, `"2048x512 (4:1 Wide)"`

### 4.6 Async Requests

For longer-running jobs, use the `/run` endpoint (returns immediately with a job ID) and poll `/status`:

```bash
# Submit job
curl -X POST "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/run" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input": {"workflow": { ... }}}'

# Check status (replace JOB_ID with the id from the response)
curl "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/status/JOB_ID" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY"
```

---

## API Specification

### Input

| Field | Type | Required | Description |
|---|---|---|---|
| `input.workflow` | Object | Yes | ComfyUI workflow in API format |
| `input.images` | Array | No | Input images as `{name, image}` objects |
| `input.images[].name` | String | Yes | Filename referenced in the workflow |
| `input.images[].image` | String | Yes | Base64 encoded image string |
| `input.comfy_org_api_key` | String | No | Per-request Comfy.org API key |

> **Size Limits:** RunPod endpoints have request size limits — 10 MB for `/run`, 20 MB for `/runsync`. Large base64 input images may exceed these.

### Output

```json
{
  "id": "sync-uuid-string",
  "status": "COMPLETED",
  "output": {
    "images": [
      {
        "filename": "ComfyUI_00001_.png",
        "type": "base64",
        "data": "iVBORw0KGgoAAAANSUhEUg..."
      }
    ]
  },
  "delayTime": 123,
  "executionTime": 4567
}
```

| Field | Type | Description |
|---|---|---|
| `output.images` | Array | Generated images |
| `output.images[].filename` | String | Filename assigned by ComfyUI |
| `output.images[].type` | String | `"base64"` or `"s3_url"` (if S3 configured) |
| `output.images[].data` | String | Base64 string or S3 URL |
| `output.errors` | Array | Non-fatal errors/warnings (if any) |

---

## Environment Variables

### Required

None. The endpoint works out of the box with no environment variables.

### Optional

| Variable | Description | Default |
|---|---|---|
| **S3 Upload** | | |
| `BUCKET_ENDPOINT_URL` | S3 endpoint URL (enables S3 upload) | — |
| `BUCKET_ACCESS_KEY_ID` | AWS access key ID | — |
| `BUCKET_SECRET_ACCESS_KEY` | AWS secret access key | — |
| **General** | | |
| `COMFY_ORG_API_KEY` | Comfy.org API key for API Nodes | — |
| `COMFY_LOG_LEVEL` | Logging: `DEBUG`, `INFO`, `WARNING`, `ERROR` | `DEBUG` |
| `REFRESH_WORKER` | Restart worker after each job (`true`/`false`) | `false` |
| **Advanced** | | |
| `WEBSOCKET_RECONNECT_ATTEMPTS` | Websocket reconnection attempts | `5` |
| `WEBSOCKET_RECONNECT_DELAY_S` | Delay between reconnection attempts (seconds) | `3` |
| `WEBSOCKET_TRACE` | Enable websocket frame tracing | `false` |

---

## Cost Estimates

All costs are based on [RunPod serverless pricing](https://www.runpod.io/pricing-page) for an A100 80GB.

### Per Image Edit

| Worker Type | Hourly Rate | ~60s Generation | ~90s Generation |
|---|---|---|---|
| **Flex** (scale to zero) | $2.72/hr | **~$0.045** | **~$0.068** |
| **Active** (always on) | $2.17/hr | **~$0.036** | **~$0.054** |

### Keeping a Worker Running 24/7 (Active)

| Period | Cost |
|---|---|
| Per hour | $2.17 |
| Per day | $52.08 |
| Per month (30 days) | $1,562 |

### Recommended Configuration

| Use Case | Min Workers | Max Workers | Approx. Monthly Cost |
|---|---|---|---|
| **Development/testing** | 0 (Flex) | 1 | Pay per request only (~$0.05/image) |
| **Low traffic** (< 40 images/hr) | 0 (Flex) | 1 | Pay per request only |
| **Production** (instant response) | 1 (Active) | 3 | ~$1,562/mo base + Flex overflow |
| **High throughput** | 2 (Active) | 5 | ~$3,124/mo base + Flex overflow |

---

## Troubleshooting

### OOM (Out of Memory) on 48GB GPUs

```
Allocation on device would exceed allowed memory (out of memory)
Currently allocated: 44.05 GiB
```

The model requires ~41–49 GB VRAM. 48 GB GPUs (A40, A6000, L40S) only have ~44 GiB usable after driver overhead. **Use an A100 80GB** — this is the minimum GPU that reliably runs this model without block swapping.

### Docker Push 502 Errors

```
received unexpected HTTP status: 502 Bad Gateway
```

Docker Hub's backend struggles with 50+ GB layers. Retry the push — Docker skips already-uploaded layers:

```bash
docker push your-username/worker-comfyui:latest-hunyuan-instruct-nf4
```

If it keeps failing, push to GHCR instead (see [Step 2](#step-2-push-to-a-container-registry)).

### Cold Start Takes Too Long

The first-ever cold start pulls the ~55 GB image. Subsequent cold starts only load the model (~2–5 min). To eliminate cold starts entirely, set `Min Workers: 1` (Active worker) — but this costs $2.17/hr continuously.

### Endpoint Shows "Downloading" for a Long Time

RunPod is pulling the Docker image. For a ~55 GB image, the first pull takes 10–30 minutes. This only happens once per worker node — the image is cached after that.

### Blank Image / "Prompt executed in 0.00 seconds"

If the endpoint returns a tiny blank PNG and the logs show `Prompt executed in 0.00 seconds`, the model didn't actually run. Common causes:

1. **bitsandbytes assertion error** — check logs for `assert module.weight.shape[1] == 1`. This means PyTorch is too old. The Comfy_HunyuanImage3 node requires `torch>=2.8.0`. The Dockerfile force-upgrades PyTorch — if you see this error, rebuild the image.
2. **Input image not sent** — if using the image editing workflow, make sure the `images` array contains actual base64 data, not the placeholder string `"<base64 encoded image>"`.
3. **Resolution format wrong** — the `resolution` field must use the exact format `"1024x1024 (1:1 Square)"`, not bare `"1024x1024"`. See [Resolution Options](#45-resolution-options).

### Model Not Found

If the worker logs show `no HunyuanImage-3.0-* dirs found`, the model wasn't baked into the image correctly. Verify the image was built with `MODEL_TYPE=hunyuan-instruct-nf4` and check that `/comfyui/models/HunyuanImage-3.0-Instruct-Distil-NF4/` exists inside the container.

---

## Available Docker Image Targets

| MODEL_TYPE | Description | Approx. Image Size | Min GPU |
|---|---|---|---|
| `base` | ComfyUI only, no models | ~8 GB | Any |
| `sdxl` | Stable Diffusion XL | ~15 GB | 16 GB+ |
| `sd3` | Stable Diffusion 3 (needs HF token) | ~12 GB | 16 GB+ |
| `flux1-schnell` | FLUX.1 schnell (needs HF token) | ~20 GB | 24 GB+ |
| `flux1-dev` | FLUX.1 dev (needs HF token) | ~20 GB | 24 GB+ |
| `flux1-dev-fp8` | FLUX.1 dev FP8 quantized | ~15 GB | 24 GB+ |
| `z-image-turbo` | Z-Image Turbo | ~15 GB | 24 GB+ |
| `hunyuan-instruct-nf4` | HunyuanImage 3.0 Instruct Distil NF4 | **~55 GB** | **A100 80GB** |

---

## Alternative: Deploy on a GPU Pod (Interactive)

If the serverless deployment isn't working or you need to debug interactively, you can run ComfyUI with the full web UI on a RunPod GPU Pod.

### Create the Pod

1. Go to [RunPod Pods Console](https://www.runpod.io/console/pods)
2. Click **+ GPU Pod**
3. Configure:

| Setting | Value |
|---|---|
| GPU | A100 80GB (or RTX PRO 6000 / any 48GB+ GPU) |
| Template | ComfyUI (RunPod's official template) |
| Container Disk | 100 GB |
| Volume Disk | 60 GB (persists across restarts) |
| Expose HTTP Ports | `8188` |

4. Click **Deploy** (~$1.64/hr for A100 80GB)

### Run the Setup Script

Open the pod's web terminal or SSH in and paste this entire block:

```bash
# Install Comfy_HunyuanImage3 custom nodes
cd /workspace/runpod-slim/ComfyUI/custom_nodes
git clone https://github.com/EricRollei/Comfy_HunyuanImage3
cd Comfy_HunyuanImage3
/workspace/runpod-slim/ComfyUI/.venv/bin/pip install -r requirements.txt
/workspace/runpod-slim/ComfyUI/.venv/bin/pip install "diffusers>=0.31.0" "transformers>=4.47.0,<5.0.0" "bitsandbytes>=0.48.2" "accelerate>=1.2.1" "huggingface_hub[hf_xet]"

# Download the model (~48 GB, takes 10-30 min)
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    'EricRollei/HunyuanImage-3.0-Instruct-Distil-NF4-v2',
    local_dir='/workspace/runpod-slim/ComfyUI/models/HunyuanImage-3.0-Instruct-Distil-NF4'
)
"
ln -s /workspace/runpod-slim/ComfyUI/models/HunyuanImage-3.0-Instruct-Distil-NF4 /workspace/runpod-slim/ComfyUI/models/HunyuanImage-3.0-Instruct-Distil-NF4-v2

# Kill existing ComfyUI and restart with the venv
pkill -f "main.py" 2>/dev/null; sleep 2
cd /workspace/runpod-slim/ComfyUI
.venv/bin/python main.py --listen 0.0.0.0 --port 8188
```

> **Important:** Packages must be installed into the `.venv` (using `.venv/bin/pip`), and ComfyUI must be started with `.venv/bin/python`. The system Python has mismatched torchvision that will crash ComfyUI. Also, `transformers` must be pinned to `<5.0.0` -- version 5.x breaks NF4 model loading.

Total setup time: ~20-40 minutes (mostly model download). The model download only happens once if you use a persistent volume.

### Access the Web UI

Click **Connect** on your pod in the RunPod dashboard, then click the **HTTP 8188** link.

### Test with curl

From a second terminal tab on the pod, send a text-to-image request:

```bash
curl -X POST http://localhost:8188/prompt -H "Content-Type: application/json" -d '{"prompt":{"1":{"inputs":{"model_name":"HunyuanImage-3.0-Instruct-Distil-NF4","force_reload":false,"attention_impl":"sdpa","moe_impl":"eager","vram_reserve_gb":30,"blocks_to_swap":0},"class_type":"HunyuanInstructLoader"},"2":{"inputs":{"model":["1",0],"prompt":"A golden retriever sitting on a beach at sunset","bot_task":"image","seed":42,"system_prompt":"dynamic","resolution":"1024x1024 (1:1 Square)","steps":-1,"guidance_scale":-1,"flow_shift":2.8,"max_new_tokens":2048,"verbose":0},"class_type":"HunyuanInstructGenerate"},"3":{"inputs":{"images":["2",0]},"class_type":"PreviewImage"}}}'
```

Watch the first terminal for model loading and diffusion progress. The generated image will appear in the web UI's preview node.

### Stop the Pod When Done

Pods charge continuously while running. **Stop or delete the pod** when you're done. The model stays on the persistent volume -- next time you start the pod, re-run the setup script and it skips the download.

---

## Getting the Workflow JSON

To create your own workflow:

1. Open ComfyUI in a browser
2. Install the [Comfy_HunyuanImage3](https://github.com/EricRollei/Comfy_HunyuanImage3) custom nodes
3. Build your workflow using the Hunyuan Instruct nodes
4. Go to **Workflow > Export (API)**
5. Use the exported JSON as the `input.workflow` value in your API requests

See [`test_resources/workflows/`](./test_resources/workflows/) for example workflows.

---

## Further Documentation

- **[Configuration Guide](docs/configuration.md):** Full list of environment variables (including S3 setup)
- **[Development Guide](docs/development.md):** Setting up a local environment for development and testing
