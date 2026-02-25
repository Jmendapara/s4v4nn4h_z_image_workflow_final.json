# worker-comfyui

> [ComfyUI](https://github.com/comfyanonymous/ComfyUI) as a serverless API on [RunPod](https://www.runpod.io/)

<p align="center">
  <img src="assets/worker_sitting_in_comfy_chair.jpg" title="Worker sitting in comfy chair" />
</p>

[![RunPod](https://api.runpod.io/badge/runpod-workers/worker-comfyui)](https://www.runpod.io/console/hub/runpod-workers/worker-comfyui)

---

This project allows you to run ComfyUI workflows as a serverless API endpoint on the RunPod platform. Submit workflows via API calls and receive generated images as base64 strings or S3 URLs.

## Table of Contents

- [Quickstart](#quickstart)
- [Building the Docker Image](#building-the-docker-image)
- [Available Docker Images](#available-docker-images)
- [API Specification](#api-specification)
- [Usage](#usage)
- [Getting the Workflow JSON](#getting-the-workflow-json)
- [Further Documentation](#further-documentation)

---

## Quickstart

1.  🐳 Choose one of the [available Docker images](#available-docker-images) for your serverless endpoint (e.g., `runpod/worker-comfyui:<version>-sd3`).
2.  📄 Follow the [Deployment Guide](docs/deployment.md) to set up your RunPod template and endpoint.
3.  ⚙️ Optionally configure the worker (e.g., for S3 upload) using environment variables - see the full [Configuration Guide](docs/configuration.md).
4.  🧪 Pick an example workflow from [`test_resources/workflows/`](./test_resources/workflows/) or [get your own](#getting-the-workflow-json).
5.  🚀 Follow the [Usage](#usage) steps below to interact with your deployed endpoint.

## Building the Docker Image

These images are large (10–30 GB depending on model) and typically can't be built on a local machine. Below are two methods for building remotely.

### Prerequisites

- A [Docker Hub](https://hub.docker.com/) account with an [access token](https://hub.docker.com/settings/security)
- The repo pushed to GitHub (for the cloud build script)

### Method 1: Build on a Cloud Server (Recommended)

Use a cheap cloud VPS (e.g., [Hetzner Cloud](https://console.hetzner.cloud/)) to build and push the image. No GPU is required — you only need CPU, disk space, and internet.

**1. Create a server**

| Setting          | Value                            |
| ---------------- | -------------------------------- |
| Provider         | Hetzner Cloud (or any VPS)       |
| OS               | Ubuntu 24.04                     |
| Server type      | CPX41 (4 vCPU, 16 GB RAM)       |
| Disk             | 160 GB (included with CPX41)     |
| Estimated cost   | ~$0.03/hour                      |

**2. SSH into the server**

```bash
ssh root@YOUR_SERVER_IP
```

**3. Install Docker**

```bash
curl -fsSL https://get.docker.com | sh
systemctl start docker
```

**4. Set environment variables**

```bash
export DOCKERHUB_USERNAME="your-dockerhub-username"
export DOCKERHUB_TOKEN="dckr_pat_your_access_token"
export IMAGE_TAG="your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4"
export MODEL_TYPE="hunyuan-instruct-nf4"
```

Available `MODEL_TYPE` values:

| MODEL_TYPE               | Description                              | Approx. Image Size |
| ------------------------ | ---------------------------------------- | ------------------- |
| `base`                   | ComfyUI only, no models                  | ~8 GB               |
| `sdxl`                   | Stable Diffusion XL                      | ~15 GB              |
| `sd3`                    | Stable Diffusion 3 (needs HF token)      | ~12 GB              |
| `flux1-schnell`          | FLUX.1 schnell (needs HF token)          | ~20 GB              |
| `flux1-dev`              | FLUX.1 dev (needs HF token)              | ~20 GB              |
| `flux1-dev-fp8`          | FLUX.1 dev FP8 quantized                 | ~15 GB              |
| `z-image-turbo`          | Z-Image Turbo                            | ~15 GB              |
| `hunyuan-instruct-nf4`   | HunyuanImage 3.0 Instruct Distil NF4    | ~25 GB              |

For models that require a HuggingFace token (`sd3`, `flux1-schnell`, `flux1-dev`), also set:

```bash
export HUGGINGFACE_ACCESS_TOKEN="hf_your_token"
```

**5. Run the build script**

```bash
curl -fsSL https://raw.githubusercontent.com/Jmendapara/s4v4nn4h_z_image_workflow_final.json/main/scripts/build-on-pod.sh | bash
```

This clones the repo, builds the Docker image with the model baked in, and pushes it to Docker Hub. Expect 30–60 minutes depending on model size and server bandwidth.

**6. Delete the server** when the build finishes to stop charges.

### Method 2: Build via GitHub Actions

Use the **"Build & Push Single Target"** workflow (`.github/workflows/build-and-push.yml`).

**1. Configure GitHub Secrets and Variables**

Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions**.

Secrets:

| Secret                     | Value                                  |
| -------------------------- | -------------------------------------- |
| `DOCKERHUB_USERNAME`       | Your Docker Hub username               |
| `DOCKERHUB_TOKEN`          | Your Docker Hub access token           |
| `HUGGINGFACE_ACCESS_TOKEN` | HuggingFace token (for gated models)   |

Variables:

| Variable         | Value                                          |
| ---------------- | ---------------------------------------------- |
| `DOCKERHUB_REPO` | Your Docker Hub username or org                 |
| `DOCKERHUB_IMG`  | Image name (e.g., `worker-comfyui`)             |

**2. Run the workflow**

1. Go to **Actions** → **"Build & Push Single Target"** → **Run workflow**
2. Select your target (e.g., `hunyuan-instruct-nf4`) and set a version tag
3. Click **Run workflow**

> **Note:** Large targets like `hunyuan-instruct-nf4` may exceed GitHub Actions runner disk space (~30 GB free after cleanup). For large images, use Method 1 instead. Smaller targets like `base`, `sdxl`, and `z-image-turbo` work fine with GitHub Actions.

### Deploying to RunPod

Once the image is pushed to Docker Hub:

1. Go to [RunPod Serverless Console](https://www.runpod.io/console/serverless)
2. Click **+ New Endpoint**
3. Configure:

| Setting          | Value                                                                  |
| ---------------- | ---------------------------------------------------------------------- |
| Container Image  | `your-dockerhub-username/worker-comfyui:latest-hunyuan-instruct-nf4`   |
| GPU              | A100 80GB (for hunyuan), or A40/L40/RTX 4090 for smaller models        |
| Min Workers      | 0 (scales to zero when idle)                                            |
| Max Workers      | 1 (or more for higher throughput)                                       |
| Container Disk   | 20 GB                                                                   |
| Idle Timeout     | 5 seconds                                                               |

4. Click **Create** and note your **Endpoint ID**

Test with:

```bash
curl -X POST "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/runsync" \
  -H "Authorization: Bearer YOUR_RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input": {"workflow": { ... your ComfyUI API workflow JSON ... }}}'
```

## Available Docker Images

These images are available on Docker Hub under `runpod/worker-comfyui`:

- **`runpod/worker-comfyui:<version>-base`**: Clean ComfyUI install with no models.
- **`runpod/worker-comfyui:<version>-flux1-schnell`**: Includes checkpoint, text encoders, and VAE for [FLUX.1 schnell](https://huggingface.co/black-forest-labs/FLUX.1-schnell).
- **`runpod/worker-comfyui:<version>-flux1-dev`**: Includes checkpoint, text encoders, and VAE for [FLUX.1 dev](https://huggingface.co/black-forest-labs/FLUX.1-dev).
- **`runpod/worker-comfyui:<version>-sdxl`**: Includes checkpoint and VAEs for [Stable Diffusion XL](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0).
- **`runpod/worker-comfyui:<version>-sd3`**: Includes checkpoint for [Stable Diffusion 3 medium](https://huggingface.co/stabilityai/stable-diffusion-3-medium).

Replace `<version>` with the current release tag, check the [releases page](https://github.com/runpod-workers/worker-comfyui/releases) for the latest version.

## API Specification

The worker exposes standard RunPod serverless endpoints (`/run`, `/runsync`, `/health`). By default, images are returned as base64 strings. You can configure the worker to upload images to an S3 bucket instead by setting specific environment variables (see [Configuration Guide](docs/configuration.md)).

Use the `/runsync` endpoint for synchronous requests that wait for the job to complete and return the result directly. Use the `/run` endpoint for asynchronous requests that return immediately with a job ID; you'll need to poll the `/status` endpoint separately to get the result.

### Input

```json
{
  "input": {
    "workflow": {
      "6": {
        "inputs": {
          "text": "a ball on the table",
          "clip": ["30", 1]
        },
        "class_type": "CLIPTextEncode",
        "_meta": {
          "title": "CLIP Text Encode (Positive Prompt)"
        }
      }
    },
    "images": [
      {
        "name": "input_image_1.png",
        "image": "data:image/png;base64,iVBOR..."
      }
    ]
  }
}
```

The following tables describe the fields within the `input` object:

| Field Path                | Type   | Required | Description                                                                                                                                |
| ------------------------- | ------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `input`                   | Object | Yes      | Top-level object containing request data.                                                                                                  |
| `input.workflow`          | Object | Yes      | The ComfyUI workflow exported in the [required format](#getting-the-workflow-json).                                                        |
| `input.images`            | Array  | No       | Optional array of input images. Each image is uploaded to ComfyUI's `input` directory and can be referenced by its `name` in the workflow. |
| `input.comfy_org_api_key` | String | No       | Optional per-request Comfy.org API key for API Nodes. Overrides the `COMFY_ORG_API_KEY` environment variable if both are set.              |

#### `input.images` Object

Each object within the `input.images` array must contain:

| Field Name | Type   | Required | Description                                                                                                                       |
| ---------- | ------ | -------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `name`     | String | Yes      | Filename used to reference the image in the workflow (e.g., via a "Load Image" node). Must be unique within the array.            |
| `image`    | String | Yes      | Base64 encoded string of the image. A data URI prefix (e.g., `data:image/png;base64,`) is optional and will be handled correctly. |

> [!NOTE]
>
> **Size Limits:** RunPod endpoints have request size limits (e.g., 10MB for `/run`, 20MB for `/runsync`). Large base64 input images can exceed these limits. See [RunPod Docs](https://docs.runpod.io/docs/serverless-endpoint-urls).

### Output

> [!WARNING]
>
> **Breaking Change in Output Format (5.0.0+)**
>
> Versions `< 5.0.0` returned the primary image data (S3 URL or base64 string) directly within an `output.message` field.
> Starting with `5.0.0`, the output format has changed significantly, see below

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

| Field Path      | Type             | Required | Description                                                                                                 |
| --------------- | ---------------- | -------- | ----------------------------------------------------------------------------------------------------------- |
| `output`        | Object           | Yes      | Top-level object containing the results of the job execution.                                               |
| `output.images` | Array of Objects | No       | Present if the workflow generated images. Contains a list of objects, each representing one output image.   |
| `output.errors` | Array of Strings | No       | Present if non-fatal errors or warnings occurred during processing (e.g., S3 upload failure, missing data). |

#### `output.images`

Each object in the `output.images` array has the following structure:

| Field Name | Type   | Description                                                                                     |
| ---------- | ------ | ----------------------------------------------------------------------------------------------- |
| `filename` | String | The original filename assigned by ComfyUI during generation.                                    |
| `type`     | String | Indicates the format of the data. Either `"base64"` or `"s3_url"` (if S3 upload is configured). |
| `data`     | String | Contains either the base64 encoded image string or the S3 URL for the uploaded image file.      |

> [!NOTE]
> The `output.images` field provides a list of all generated images (excluding temporary ones).
>
> - If S3 upload is **not** configured (default), `type` will be `"base64"` and `data` will contain the base64 encoded image string.
> - If S3 upload **is** configured, `type` will be `"s3_url"` and `data` will contain the S3 URL. See the [Configuration Guide](docs/configuration.md#example-s3-response) for an S3 example response.
> - Clients interacting with the API need to handle this list-based structure under `output.images`.

## Usage

To interact with your deployed RunPod endpoint:

1.  **Get API Key:** Generate a key in RunPod [User Settings](https://www.runpod.io/console/serverless/user/settings) (`API Keys` section).
2.  **Get Endpoint ID:** Find your endpoint ID on the [Serverless Endpoints](https://www.runpod.io/console/serverless/user/endpoints) page or on the `Overview` page of your endpoint.

### Generate Image (Sync Example)

Send a workflow to the `/runsync` endpoint (waits for completion). Replace `<api_key>` and `<endpoint_id>`. The `-d` value should contain the [JSON input described above](#input).

```bash
curl -X POST \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"input":{"workflow":{... your workflow JSON ...}}}' \
  https://api.runpod.ai/v2/<endpoint_id>/runsync
```

You can also use the `/run` endpoint for asynchronous jobs and then poll the `/status` to see when the job is done. Or you [add a `webhook` into your request](https://docs.runpod.io/serverless/endpoints/send-requests#webhook-notifications) to be notified when the job is done.

Refer to [`test_input.json`](./test_input.json) for a complete input example.

## Getting the Workflow JSON

To get the correct `workflow` JSON for the API:

1.  Open ComfyUI in your browser.
2.  In the top navigation, select `Workflow > Export (API)`
3.  A `workflow.json` file will be downloaded. Use the content of this file as the value for the `input.workflow` field in your API requests.

## Further Documentation

- **[Deployment Guide](docs/deployment.md):** Detailed steps for deploying on RunPod.
- **[Configuration Guide](docs/configuration.md):** Full list of environment variables (including S3 setup).
- **[Customization Guide](docs/customization.md):** Adding custom models and nodes (Network Volumes, Docker builds).
- **[Development Guide](docs/development.md):** Setting up a local environment for development & testing
- **[CI/CD Guide](docs/ci-cd.md):** Information about the automated Docker build and publish workflows.
- **[Acknowledgments](docs/acknowledgments.md):** Credits and thanks
