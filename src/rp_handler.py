import runpod
from runpod.serverless.utils import rp_upload
import json
import urllib.request
import time
import os
import requests
import base64
from io import BytesIO

COMFY_API_AVAILABLE_INTERVAL_MS = 50
COMFY_API_AVAILABLE_MAX_RETRIES = 500
COMFY_POLLING_INTERVAL_MS = int(os.environ.get("COMFY_POLLING_INTERVAL_MS", 250))
COMFY_POLLING_MAX_RETRIES = int(os.environ.get("COMFY_POLLING_MAX_RETRIES", 500))
COMFY_HOST = "127.0.0.1:8188"
REFRESH_WORKER = os.environ.get("REFRESH_WORKER", "false").lower() == "true"


def validate_input(job_input):
    if job_input is None:
        return None, "Please provide input"
    if isinstance(job_input, str):
        try:
            job_input = json.loads(job_input)
        except json.JSONDecodeError:
            return None, "Invalid JSON format in input"
    workflow = job_input.get("workflow")
    if workflow is None:
        return None, "Missing 'workflow' parameter"
    images = job_input.get("images")
    if images is not None:
        if not isinstance(images, list) or not all("name" in image and "image" in image for image in images):
            return None, "'images' must be a list of objects with 'name' and 'image' keys"
    return {"workflow": workflow, "images": images}, None


def check_server(url, retries=500, delay=50):
    for _ in range(retries):
        try:
            response = requests.get(url)
            if response.status_code == 200:
                print("runpod-worker-comfy - API is reachable")
                return True
        except requests.RequestException:
            pass
        time.sleep(delay / 1000)
    print(f"runpod-worker-comfy - Failed to connect to server at {url} after {retries} attempts.")
    return False


def upload_images(images):
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}
    responses, upload_errors = [], []
    for image in images:
        name = image["name"]
        blob = base64.b64decode(image["image"])
        files = {"image": (name, BytesIO(blob), "image/png"), "overwrite": (None, "true")}
        response = requests.post(f"http://{COMFY_HOST}/upload/image", files=files)
        if response.status_code != 200:
            upload_errors.append(f"Error uploading {name}: {response.text}")
        else:
            responses.append(f"Successfully uploaded {name}")
    return {"status": "error" if upload_errors else "success", "message": "Upload result", "details": upload_errors or responses}


def queue_workflow(workflow):
    data = json.dumps({"prompt": workflow}).encode("utf-8")
    req = urllib.request.Request(f"http://{COMFY_HOST}/prompt", data=data)
    return json.loads(urllib.request.urlopen(req).read())


def get_history(prompt_id):
    with urllib.request.urlopen(f"http://{COMFY_HOST}/history/{prompt_id}") as response:
        return json.loads(response.read())


def base64_encode(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def process_video_output(outputs):
    output_path = os.environ.get("COMFY_OUTPUT_PATH", "/comfyui/output")
    for node_output in outputs.values():
        if "videos" in node_output:
            for video in node_output["videos"]:
                file_path = os.path.join(output_path, video["subfolder"], video["filename"])
                if os.path.exists(file_path):
                    video_base64 = base64_encode(file_path)
                    return {
                        "status": "success",
                        "message": video_base64
                    }
    return {
        "status": "failed",
        "message": "No video output found. Ensure your workflow ends with a SaveVideo node."
    }


prompt_status = {}

def handler(job):
    job_id = job["id"]
    job_input = job["input"]

    # First request, initiate the job
    if job_id not in prompt_status:
        validated, error = validate_input(job_input)
        if error:
            return {"status": "failed", "message": error}

        workflow, images = validated["workflow"], validated.get("images")
        check_server(f"http://{COMFY_HOST}", COMFY_API_AVAILABLE_MAX_RETRIES, COMFY_API_AVAILABLE_INTERVAL_MS)

        upload_result = upload_images(images)
        if upload_result["status"] == "error":
            return upload_result

        try:
            prompt_id = queue_workflow(workflow)["prompt_id"]
            prompt_status[job_id] = prompt_id
            print(f"runpod-worker-comfy - queued workflow with ID {prompt_id}")
            return {"status": "in_progress", "message": "Workflow queued."}
        except Exception as e:
            return {"status": "failed", "message": f"Error queuing workflow: {str(e)}"}

    # Poll for existing job
    prompt_id = prompt_status[job_id]
    try:
        history = get_history(prompt_id)
        if prompt_id not in history or not history[prompt_id].get("outputs"):
            return {"status": "in_progress", "message": "Waiting for output..."}
    except Exception:
        return {"status": "in_progress", "message": "Waiting for output..."}

    result = process_video_output(history[prompt_id].get("outputs"))
    result["refresh_worker"] = REFRESH_WORKER
    return result


if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})