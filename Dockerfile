# Stage 1: Setup base with ComfyUI
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

RUN apt-get update && apt-get install -y \
    python3.10 python3-pip git wget aria2 libgl1 libgl1-mesa-glx libglib2.0-0 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

RUN pip install comfy-cli

RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.3.27

WORKDIR /comfyui

RUN pip install runpod requests

ADD src/extra_model_paths.yaml ./
WORKDIR /

ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

ADD *snapshot*.json /

RUN /restore_snapshot.sh
RUN git clone https://github.com/SOELexicon/ComfyUI-LexTools /comfyui/custom_nodes/ComfyUI-LexTools

# Stage 2: Download WAN and utility models
FROM base AS downloader

WORKDIR /comfyui

RUN mkdir -p models/checkpoints models/vae models/unet models/clip models/vision

# --- WAN (lighter I2V, better T2V) ---
RUN aria2c -x 16 -s 16 -d models/unet -o wan2.1_t2v_14B_fp8_e4m3fn.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_fp8_e4m3fn.safetensors
RUN aria2c -x 16 -s 16 -d models/vae -o wan_2.1_vae.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors
RUN aria2c -x 16 -s 16 -d models/clip -o umt5_xxl_fp8_e4m3fn_scaled.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
RUN aria2c -x 16 -s 16 -d models/vision -o clip_vision_h.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors

# Stage 3: Final runtime
FROM base AS final
COPY --from=downloader /comfyui/models /comfyui/models
CMD ["/start.sh"]
