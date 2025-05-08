# ---------- Base image ----------
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS base

# ---------- Install Python, pip, and dependencies ----------
RUN apt-get update && \
    apt-get install -y git ffmpeg libglib2.0-0 libsm6 libxrender1 libxext6 aria2 python3 python3-pip && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    pip install --upgrade pip

# ---------- Install ComfyUI CLI and required Python packages ----------
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 && \
    pip install comfyui-cli

# ---------- Set working directory ----------
WORKDIR /workspace

# ---------- Clone and install custom nodes ----------
RUN comfy node install https://github.com/SOELexicon/ComfyUI-LexTools.git && \
    comfy node install https://github.com/Wan-AI/Wan-ComfyUI.git

# ---------- Create model directories ----------
RUN mkdir -p /workspace/models/vae /workspace/models/unet /workspace/models/clip /workspace/models/vision

# ---------- Download model weights using aria2 with progress ----------
RUN echo "Downloading model weights with aria2..." && \
    aria2c -x 16 -s 16 --console-log-level=notice -d /workspace/models/unet -o wan2.1_i2v_480p_7B_fp16.safetensors \
      "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_480p_7B_fp16.safetensors" && \
    aria2c -x 16 -s 16 --console-log-level=notice -d /workspace/models/unet -o wan2.1_t2v_3.6B_fp16.safetensors \
      "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_3.6B_fp16.safetensors" && \
    aria2c -x 16 -s 16 --console-log-level=notice -d /workspace/models/vae -o wan_2.1_vae.safetensors \
      "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" && \
    aria2c -x 16 -s 16 --console-log-level=notice -d /workspace/models/clip -o umt5_xxl_fp8_e4m3fn_scaled.safetensors \
      "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" && \
    aria2c -x 16 -s 16 --console-log-level=notice -d /workspace/models/vision -o clip_vision_h.safetensors \
      "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"

# ---------- Copy handler ----------
COPY /src/rp_handler.py /workspace/rp_handler.py

# ---------- Set entrypoint for RunPod ----------
ENV PYTHONUNBUFFERED=1
CMD ["python3", "/workspace/rp_handler.py"]
