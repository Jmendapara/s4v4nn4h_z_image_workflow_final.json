# HunyuanImage 3.0 — Serverless ComfyUI Worker

> [ComfyUI](https://github.com/comfyanonymous/ComfyUI) + HunyuanImage 3.0 Instruct Distil ([NF4](https://huggingface.co/EricRollei/HunyuanImage-3.0-Instruct-Distil-NF4-v2) or [INT8](https://huggingface.co/EricRollei/HunyuanImage-3.0-Instruct-Distil-INT8-v2)) as a serverless API on [RunPod](https://www.runpod.io/)

---

## Table of Contents

- [Overview](#overview)
- [Model Variants](#model-variants)
- [Step 1: Build the Docker Image](#step-1-build-the-docker-image)
- [Step 2: Push to a Container Registry](#step-2-push-to-a-container-registry)
- [Step 3: Deploy on RunPod](#step-3-deploy-on-runpod)
- [Step 4: Test Your Endpoint](#step-4-test-your-endpoint)
- [API Specification](#api-specification)
- [Environment Variables](#environment-variables)
- [Cost Estimates](#cost-estimates)
- [Multi-Image Fusion](#multi-image-fusion)
- [Troubleshooting](#troubleshooting)

---

## Overview

This project packages ComfyUI with a HunyuanImage 3.0 Instruct Distil model baked into a Docker image. Two quantization variants are supported — **NF4** (4-bit, smaller, fits A100 80GB) and **INT8** (8-bit, higher quality, needs 96GB+ VRAM). The image runs as a serverless worker on RunPod — you send a workflow via API and receive generated/edited images back as base64 strings or S3 URLs.

The model is baked directly into the Docker image. No network volume is required.

## Model Variants

| Property | NF4 | INT8 |
|---|---|---|
| Model | [Instruct Distil NF4 v2](https://huggingface.co/EricRollei/HunyuanImage-3.0-Instruct-Distil-NF4-v2) | [Instruct Distil INT8 v2](https://huggingface.co/EricRollei/HunyuanImage-3.0-Instruct-Distil-INT8-v2) |
| Architecture | Mixture-of-Experts Diffusion Transformer | Mixture-of-Experts Diffusion Transformer |
| Parameters | 80B total, 13B active per token | 80B total, 13B active per token |
| Quantization | NF4 (4-bit) via bitsandbytes | INT8 (8-bit) via bitsandbytes |
| Diffusion Steps | 8 (CFG-distilled) | 8 (CFG-distilled) |
| Capabilities | Text-to-image, image editing, multi-image fusion | Text-to-image, image editing, multi-image fusion |
| On-disk Size | ~48 GB | ~83 GB |
| Docker Image Size | ~55 GB | ~90 GB |
| VRAM Required | ~41–49 GB | ~92–100 GB |
| Recommended GPU | A100 80GB | RTX 6000 Blackwell 96GB / H100 80GB (with block swap) |
| `MODEL_TYPE` env | `hunyuan-instruct-nf4` | `hunyuan-instruct-int8` |
| ComfyUI Nodes | [Comfy_HunyuanImage3](https://github.com/EricRollei/Comfy_HunyuanImage3) | [Comfy_HunyuanImage3](https://github.com/EricRollei/Comfy_HunyuanImage3) |

**When to choose NF4 vs INT8:**
- **NF4** — Best value. Fits on A100 80GB without block swapping. Good image quality, fastest cold starts due to smaller image.
- **INT8** — Better image quality (keeps attention projections and embeddings in BF16). Requires 96GB+ VRAM to run without block swapping, or 80GB with 4-8 blocks swapped to CPU.

**GPU Compatibility:**

Both Docker images are built with CUDA 12.8 PyTorch, supporting A100 (sm_80), H100 (sm_90), and Blackwell (sm_120) GPUs.

| | A100 80GB | H100 80GB | RTX 6000 Blackwell 96GB |
|---|---|---|---|
| **NF4 text-to-image / edit** | Works (`blocks_to_swap: 0`) | Works | Works |
| **NF4 3-image fusion** | Likely OOMs | Likely OOMs | Works (`blocks_to_swap: 16`) |
| **INT8 text-to-image / edit** | `blocks_to_swap: 4-8` | `blocks_to_swap: 4-8` | Works (`blocks_to_swap: 0`) |
| **INT8 3-image fusion** | Likely OOMs | Likely OOMs | `blocks_to_swap: 16`+ |

---

## Step 1: Build the Docker Image

The image must be built on a remote server with enough disk space. A GPU is **not** needed for building.

### 1.1 Create a Cloud Server

Use a cheap VPS from [Hetzner Cloud](https://console.hetzner.cloud/) or any provider.

| Setting | NF4 | INT8 |
|---|---|---|
| Provider | Hetzner Cloud (or any VPS) | Hetzner Cloud (or any VPS) |
| OS | Ubuntu 24.04 | Ubuntu 24.04 |
| Server type | CPX51 (8 vCPU, 16 GB RAM, 240 GB disk) | Dedicated or volume-mounted (400 GB+ disk) |
| Disk | 240 GB minimum | 400 GB minimum |
| Estimated cost | ~$0.04/hour | ~$0.08/hour |

> **Important:** Docker needs space for intermediate build layers in addition to the final image. The INT8 model is ~83 GB on disk, so you need significantly more space than for NF4.

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

**For NF4:**
```bash
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_TOKEN="dckr_pat_your_access_token"
export IMAGE_TAG="your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4"
export MODEL_TYPE="hunyuan-instruct-nf4"
```

**For INT8:**
```bash
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_TOKEN="dckr_pat_your_access_token"
export IMAGE_TAG="your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-int8"
export MODEL_TYPE="hunyuan-instruct-int8"
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
4. Builds the Docker image with bitsandbytes and the selected HunyuanImage 3.0 model baked in
5. Pushes the image to Docker Hub

Expect **60–90 minutes** for NF4 or **90–150 minutes** for INT8 (larger model download and push).

### 1.6 Delete the Server

Once the push completes, **delete the server immediately** to stop charges.

---

## Step 2: Push to a Container Registry

The build script pushes to Docker Hub automatically. If the push fails (502 errors are common for 50+ GB layers), retry:

```bash
docker push your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4
# or for INT8:
docker push your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-int8
```

Docker skips layers that already uploaded successfully and only retries the failed ones.

### Alternative: Push to GitHub Container Registry

GHCR handles large layers more reliably than Docker Hub. Especially recommended for INT8 (~90 GB image). To use it instead:

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

**For NF4:**

| Setting | Value | Notes |
|---|---|---|
| **Container Image** | `your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4` | Or `ghcr.io/...` if using GHCR |
| **GPU** | **A100 80GB** | Required — 48 GB GPUs will OOM |
| **Min Workers** | `0` | Scales to zero when idle (no cost) |
| **Max Workers** | `1` | Increase for higher throughput |
| **Container Disk** | `20 GB` | Scratch space only; model is in the image |
| **Idle Timeout** | `5` seconds | How long a warm worker waits before shutting down |
| **FlashBoot** | Enabled (if available) | Speeds up cold starts |

**For INT8:**

| Setting | Value | Notes |
|---|---|---|
| **Container Image** | `your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-int8` | Or `ghcr.io/...` if using GHCR |
| **GPU** | **RTX 6000 Blackwell 96GB** or **H100/H200** | 80GB GPUs need `blocks_to_swap: 4-8` |
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
- RunPod pulls the Docker image (first time only — cached after that)
- ComfyUI starts and loads the model into GPU VRAM

The first-ever cold start takes **10–30 minutes** for NF4 (~55 GB) or **20–45 minutes** for INT8 (~90 GB) due to image pull. Subsequent cold starts take **2–5 minutes** (model loading only, image is cached).

### 4.2 Text-to-Image Request

Send a workflow to the `/runsync` endpoint. Use the `model_name` that matches your deployed image (`HunyuanImage-3.0-Instruct-Distil-NF4` or `HunyuanImage-3.0-Instruct-Distil-INT8`):

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
| `instruction` | HunyuanInstructImageEdit / MultiFusion | The edit/fusion instruction | Any text. For fusion, reference images as "image 1", "image 2", etc. |
| `bot_task` | Generate / ImageEdit / MultiFusion | Generation mode | `image` (fastest), `recaption` (medium), `think_recaption` (best quality) |
| `resolution` | Generate / MultiFusion | Output resolution | Must use exact format: `"1024x1024 (1:1 Square)"` — see full list below |
| `blocks_to_swap` | HunyuanInstructLoader | Offload transformer blocks to CPU | `0` for text-to-image/single edit; `16` for 3-image fusion on NF4. See [Multi-Image Fusion](#multi-image-fusion) |
| `force_reload` | HunyuanInstructLoader | Force model reload | Set `true` when changing `blocks_to_swap` — the model is cached and won't pick up new settings otherwise |
| `vram_reserve_gb` | HunyuanInstructLoader | VRAM to keep free for inference | `30` recommended. **Has no effect on NF4 models** — use `blocks_to_swap` instead |
| `image_1` .. `image_5` | HunyuanInstructMultiFusion | Input images for fusion | `image_1` required, `image_2`-`image_3` official, `image_4`-`image_5` experimental |
| `seed` | Generate / ImageEdit / MultiFusion | Random seed | `-1` for random, or a fixed integer |
| `steps` | Generate / ImageEdit / MultiFusion | Diffusion steps | `-1` for default (8 steps) |
| `guidance_scale` | Generate / ImageEdit / MultiFusion | CFG scale | `-1` for default (2.5) |

### 4.5 Resolution Options

The `resolution` field requires an exact string from this list (33 model-native bucket resolutions + Auto). Using a bare value like `"1024x1024"` will fail.

**Auto:**
`"Auto (model predicts)"`

**Extreme Tall (1:4 to 1:3):**
`"512x2048 (1:4 Tall)"`, `"512x1984 (~1:4 Tall)"`, `"512x1920 (4:15 Tall)"`, `"512x1856 (~1:4 Tall)"`, `"512x1792 (2:7 Tall)"`, `"512x1728 (~1:3 Tall)"`, `"512x1664 (4:13 Tall)"`, `"512x1600 (8:25 Tall)"`, `"512x1536 (1:3 Portrait)"`

**Tall Portrait (9:23 to 3:5):**
`"576x1472 (9:23 Portrait)"`, `"640x1408 (5:11 Portrait)"`, `"704x1344 (11:21 Portrait)"`, `"768x1280 (3:5 Portrait)"`

**Standard Portrait (13:19 to 15:17):**
`"832x1216 (13:19 Portrait)"`, `"896x1152 (7:9 Portrait)"`, `"960x1088 (15:17 Portrait)"`

**Square:**
`"1024x1024 (1:1 Square)"`

**Standard Landscape (17:15 to 19:13):**
`"1088x960 (17:15 Landscape)"`, `"1152x896 (9:7 Landscape)"`, `"1216x832 (19:13 Landscape)"`

**Wide Landscape (5:3 to 11:5):**
`"1280x768 (5:3 Landscape)"`, `"1344x704 (21:11 Landscape)"`, `"1408x640 (11:5 Landscape)"`, `"1472x576 (23:9 Landscape)"`

**Extreme Wide (3:1 to 4:1):**
`"1536x512 (3:1 Wide)"`, `"1600x512 (25:8 Wide)"`, `"1664x512 (13:4 Wide)"`, `"1728x512 (27:8 Wide)"`, `"1792x512 (7:2 Wide)"`, `"1856x512 (29:8 Wide)"`, `"1920x512 (15:4 Wide)"`, `"1984x512 (31:8 Wide)"`, `"2048x512 (4:1 Wide)"`

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

## Multi-Image Fusion

The model supports combining elements from **up to 3 images** into a single output using the `HunyuanInstructMultiFusion` node. 4-5 images are experimental and require significantly more VRAM.

### Multi-Image Fusion Workflow (API)

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
            "blocks_to_swap": 16
          },
          "class_type": "HunyuanInstructLoader",
          "_meta": { "title": "Hunyuan Instruct Loader" }
        },
        "2": {
          "inputs": { "image": "image1.png", "upload": "image" },
          "class_type": "LoadImage"
        },
        "3": {
          "inputs": { "image": "image2.png", "upload": "image" },
          "class_type": "LoadImage"
        },
        "4": {
          "inputs": { "image": "image3.png", "upload": "image" },
          "class_type": "LoadImage"
        },
        "5": {
          "inputs": {
            "model": ["1", 0],
            "image_1": ["2", 0],
            "image_2": ["3", 0],
            "image_3": ["4", 0],
            "instruction": "Place the subject from image 1 into the scene from image 2 with the style of image 3",
            "bot_task": "image",
            "seed": -1,
            "system_prompt": "dynamic",
            "resolution": "1024x1024 (1:1 Square)",
            "steps": -1
          },
          "class_type": "HunyuanInstructMultiFusion",
          "_meta": { "title": "Hunyuan Instruct Multi-Image Fusion" }
        },
        "6": {
          "inputs": {
            "filename_prefix": "ComfyUI",
            "images": ["5", 0]
          },
          "class_type": "SaveImage",
          "_meta": { "title": "Save Image" }
        }
      },
      "images": [
        { "name": "image1.png", "image": "<base64 image 1>" },
        { "name": "image2.png", "image": "<base64 image 2>" },
        { "name": "image3.png", "image": "<base64 image 3>" }
      ]
    }
  }'
```

### Multi-Image Fusion Input Names

The fusion node uses numbered inputs: `image_1` (required), `image_2` through `image_5` (optional). Do NOT use `images` or `image` — the node will reject them.

### VRAM Requirements for Multi-Image Fusion

Multi-image fusion uses significantly more VRAM than text-to-image or single-image editing because the MoE dispatch_mask grows O(N²) with token count. More images = more tokens = exponentially more VRAM for the dispatch mask.

| Operation | NF4 blocks_to_swap | NF4 on 96GB GPU | NF4 on 80GB GPU |
|---|---|---|---|
| Text-to-image | `0` | Works | Works |
| Single image edit | `0` | Works | Works |
| 2-image fusion | `0` | Works | May OOM — try `8` |
| **3-image fusion** | **`16`** | **Works** | **Likely OOMs even with `16`+** |

> **Critical:** If you change `blocks_to_swap` after the model is already loaded, you **must** set `"force_reload": true` in the loader. The model is cached in memory — changing `blocks_to_swap` without `force_reload` has no effect.

### Bot Task Modes

| Mode | Description | Speed | VRAM |
|---|---|---|---|
| `image` | Direct generation — prompt/instruction used as-is | Fastest | Lowest |
| `recaption` | Model rewrites prompt into detailed description first | Medium | Medium |
| `think_recaption` | Chain-of-thought reasoning, then rewrite, then generate (best quality) | Slowest | Highest (~28 GB dispatch_mask for NF4 Distil) |

For multi-image fusion, use `bot_task: "image"` to minimize VRAM usage. `think_recaption` with 3 images will almost certainly OOM on any current GPU.

---

## Troubleshooting

### OOM (Out of Memory) on 48GB GPUs

```
Allocation on device would exceed allowed memory (out of memory)
Currently allocated: 44.05 GiB
```

**NF4:** Requires ~41–49 GB VRAM. 48 GB GPUs (A40, A6000, L40S) only have ~44 GiB usable after driver overhead. **Use an A100 80GB** — this is the minimum GPU that reliably runs NF4 without block swapping.

**INT8:** Requires ~92–100 GB VRAM. **Use a 96GB+ GPU** (RTX 6000 Blackwell) without block swap, or an 80GB GPU (H100) with `blocks_to_swap: 4-8`.

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

The first-ever cold start pulls the Docker image (~55 GB for NF4, ~90 GB for INT8). Subsequent cold starts only load the model (~2–5 min). To eliminate cold starts entirely, set `Min Workers: 1` (Active worker) — but this costs $2.17/hr+ continuously.

### Endpoint Shows "Downloading" for a Long Time

RunPod is pulling the Docker image. For NF4 (~55 GB) the first pull takes 10–30 minutes; for INT8 (~90 GB) it takes 20–45 minutes. This only happens once per worker node — the image is cached after that.

### Blank Image / "Prompt executed in 0.00 seconds"

If the endpoint returns a tiny blank PNG and the logs show `Prompt executed in 0.00 seconds`, the model didn't actually run. Common causes:

1. **bitsandbytes assertion error** — check logs for `assert module.weight.shape[1] == 1`. This means PyTorch is too old. The Comfy_HunyuanImage3 node requires `torch>=2.8.0`. The Dockerfile force-upgrades PyTorch — if you see this error, rebuild the image.
2. **Input image not sent** — if using the image editing workflow, make sure the `images` array contains actual base64 data, not the placeholder string `"<base64 encoded image>"`.
3. **Resolution format wrong** — the `resolution` field must use the exact format `"1024x1024 (1:1 Square)"`, not bare `"1024x1024"`. See [Resolution Options](#45-resolution-options).

### OOM During Multi-Image Fusion (3 Images)

```
CUDA Out of Memory during multi-image fusion
Currently allocated: 57.50 GiB
Requested: 22.69 GiB
```

Multi-image fusion uses O(N²) more VRAM than single-image operations due to the MoE dispatch_mask. For 3 images on NF4:

1. Set `"blocks_to_swap": 16` (offloads ~12 GB of model weights to CPU)
2. **Set `"force_reload": true`** — if the model was already loaded with `blocks_to_swap: 0`, the cached model won't pick up the new setting
3. Use `"bot_task": "image"` (not `think_recaption` which uses ~28 GB for the dispatch mask alone)

See [Multi-Image Fusion](#multi-image-fusion) for full details.

### blocks_to_swap Has No Effect

If you change `blocks_to_swap` but VRAM usage stays the same, the model is cached from a previous load. Set `"force_reload": true` in the `HunyuanInstructLoader` inputs. This forces a full model reload with the new block swap setting.

### CUDA Error: No Kernel Image Available (Blackwell GPUs)

```
NVIDIA RTX PRO 6000 Blackwell Server Edition with CUDA capability sm_120 is not compatible
The current PyTorch install supports CUDA capabilities sm_50 sm_60 sm_70 sm_75 sm_80 sm_86 sm_90
```

The PyTorch version doesn't include Blackwell (sm_120) kernels. Fix depends on context:

- **Docker image (serverless):** Both NF4 and INT8 targets in `docker-bake.hcl` are already configured with CUDA 12.8 PyTorch which includes Blackwell kernels. Rebuild the image.
- **GPU Pod (interactive):** Upgrade PyTorch in the venv:

```bash
/workspace/runpod-slim/ComfyUI/.venv/bin/pip install --force-reinstall torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
```

The `setup-pod.sh` script auto-detects Blackwell GPUs and upgrades PyTorch automatically.

### torchvision::nms Operator Does Not Exist (GPU Pod)

```
RuntimeError: operator torchvision::nms does not exist
```

This happens when system Python's `torchvision` is loaded instead of the venv's version. Always start ComfyUI with the venv Python:

```bash
cd /workspace/runpod-slim/ComfyUI
.venv/bin/python main.py --listen 0.0.0.0 --port 8188
```

If the venv doesn't have `torchvision` installed:

```bash
/workspace/runpod-slim/ComfyUI/.venv/bin/pip install torchvision
```

### Model Not Found

If the worker logs show `no HunyuanImage-3.0-* dirs found`, the model wasn't baked into the image correctly. Verify the image was built with the correct `MODEL_TYPE` and check that the appropriate model directory exists inside the container:
- NF4: `/comfyui/models/HunyuanImage-3.0-Instruct-Distil-NF4/`
- INT8: `/comfyui/models/HunyuanImage-3.0-Instruct-Distil-INT8/`

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
| `hunyuan-instruct-int8` | HunyuanImage 3.0 Instruct Distil INT8 | **~90 GB** | **96GB+ (RTX 6000 Blackwell)** |

---

## Alternative: Deploy on a GPU Pod (Interactive)

If the serverless deployment isn't working or you need to debug interactively, you can run ComfyUI with the full web UI on a RunPod GPU Pod.

### Create the Pod

1. Go to [RunPod Pods Console](https://www.runpod.io/console/pods)
2. Click **+ GPU Pod**
3. Configure:

| Setting | NF4 | INT8 |
|---|---|---|
| GPU | A100 80GB | RTX 6000 Blackwell 96GB / H100 |
| Template | ComfyUI (RunPod's official template) | ComfyUI (RunPod's official template) |
| Container Disk | 100 GB | 200 GB |
| Volume Disk | 60 GB | 100 GB |
| Expose HTTP Ports | `8188` | `8188` |

4. Click **Deploy**

### Run the Setup Script

Open the pod's web terminal or SSH in and paste this entire block.

**For NF4:**

```bash
VENV_PIP=/workspace/runpod-slim/ComfyUI/.venv/bin/pip

# Install Comfy_HunyuanImage3 custom nodes
cd /workspace/runpod-slim/ComfyUI/custom_nodes
git clone https://github.com/EricRollei/Comfy_HunyuanImage3
cd Comfy_HunyuanImage3
$VENV_PIP install -r requirements.txt
$VENV_PIP install torchvision "diffusers>=0.31.0" "transformers>=4.47.0,<5.0.0" "bitsandbytes>=0.48.2" "accelerate>=1.2.1" "huggingface_hub[hf_xet]"

# Blackwell GPUs (RTX 6000 Blackwell, etc.) need PyTorch with CUDA 12.8 kernels:
# $VENV_PIP install --force-reinstall torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

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

**For INT8:**

```bash
VENV_PIP=/workspace/runpod-slim/ComfyUI/.venv/bin/pip

# Install Comfy_HunyuanImage3 custom nodes
cd /workspace/runpod-slim/ComfyUI/custom_nodes
git clone https://github.com/EricRollei/Comfy_HunyuanImage3
cd Comfy_HunyuanImage3
$VENV_PIP install -r requirements.txt
$VENV_PIP install torchvision "diffusers>=0.31.0" "transformers>=4.47.0,<5.0.0" "bitsandbytes>=0.48.2" "accelerate>=1.2.1" "huggingface_hub[hf_xet]"

# Blackwell GPUs (RTX 6000 Blackwell, etc.) need PyTorch with CUDA 12.8 kernels:
# $VENV_PIP install --force-reinstall torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

# Download the model (~83 GB, takes 20-60 min)
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    'EricRollei/HunyuanImage-3.0-Instruct-Distil-INT8-v2',
    local_dir='/workspace/runpod-slim/ComfyUI/models/HunyuanImage-3.0-Instruct-Distil-INT8'
)
"
ln -s /workspace/runpod-slim/ComfyUI/models/HunyuanImage-3.0-Instruct-Distil-INT8 /workspace/runpod-slim/ComfyUI/models/HunyuanImage-3.0-Instruct-Distil-INT8-v2

# Kill existing ComfyUI and restart with the venv
pkill -f "main.py" 2>/dev/null; sleep 2
cd /workspace/runpod-slim/ComfyUI
.venv/bin/python main.py --listen 0.0.0.0 --port 8188
```

> **Important notes for GPU Pod setup:**
> - All packages must be installed into the `.venv` (using `.venv/bin/pip`), and ComfyUI must be started with `.venv/bin/python`. The system Python has a mismatched `torchvision` that will crash ComfyUI with `operator torchvision::nms does not exist`.
> - `torchvision` must be explicitly installed into the venv — it's not included by default.
> - `transformers` must be pinned to `<5.0.0` — version 5.x breaks NF4/INT8 model loading with `"normal_kernel_cuda" not implemented for 'Byte'`.
> - **Blackwell GPUs** (RTX 6000 Blackwell, sm_120): Uncomment the PyTorch CUDA 12.8 upgrade line. The default PyTorch in the venv only supports up to sm_90 (H100). Without this upgrade, generation fails with `CUDA error: no kernel image is available for execution on the device`.

Total setup time: ~20-40 minutes for NF4, ~40-70 minutes for INT8 (mostly model download). The model download only happens once if you use a persistent volume.

### Access the Web UI

Click **Connect** on your pod in the RunPod dashboard, then click the **HTTP 8188** link.

### Test with curl

From a second terminal tab on the pod, send a text-to-image request. Replace the `model_name` with the variant you downloaded:

**NF4:**
```bash
curl -X POST http://localhost:8188/prompt -H "Content-Type: application/json" -d '{"prompt":{"1":{"inputs":{"model_name":"HunyuanImage-3.0-Instruct-Distil-NF4","force_reload":false,"attention_impl":"sdpa","moe_impl":"eager","vram_reserve_gb":30,"blocks_to_swap":0},"class_type":"HunyuanInstructLoader"},"2":{"inputs":{"model":["1",0],"prompt":"A golden retriever sitting on a beach at sunset","bot_task":"image","seed":42,"system_prompt":"dynamic","resolution":"1024x1024 (1:1 Square)","steps":-1,"guidance_scale":-1,"flow_shift":2.8,"max_new_tokens":2048,"verbose":0},"class_type":"HunyuanInstructGenerate"},"3":{"inputs":{"filename_prefix":"ComfyUI","images":["2",0]},"class_type":"SaveImage"}}}'
```

**INT8:**
```bash
curl -X POST http://localhost:8188/prompt -H "Content-Type: application/json" -d '{"prompt":{"1":{"inputs":{"model_name":"HunyuanImage-3.0-Instruct-Distil-INT8","force_reload":false,"attention_impl":"sdpa","moe_impl":"eager","vram_reserve_gb":30,"blocks_to_swap":0},"class_type":"HunyuanInstructLoader"},"2":{"inputs":{"model":["1",0],"prompt":"A golden retriever sitting on a beach at sunset","bot_task":"image","seed":42,"system_prompt":"dynamic","resolution":"1024x1024 (1:1 Square)","steps":-1,"guidance_scale":-1,"flow_shift":2.8,"max_new_tokens":2048,"verbose":0},"class_type":"HunyuanInstructGenerate"},"3":{"inputs":{"filename_prefix":"ComfyUI","images":["2",0]},"class_type":"SaveImage"}}}'
```

> For INT8 on 80GB GPUs, set `"blocks_to_swap": 4` (or up to 8) to offload transformer blocks to CPU.

Watch the first terminal for model loading and diffusion progress. The generated image will be saved to the `output/` folder and visible in the web UI.

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
