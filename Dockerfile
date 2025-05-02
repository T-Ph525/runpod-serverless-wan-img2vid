# Stage 1: Setup base with ComfyUI
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

RUN apt-get update && apt-get install -y \
    python3.10 python3-pip git wget libgl1 libgl1-mesa-glx libglib2.0-0 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*


RUN pip install comfy-cli

RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.3.27

WORKDIR /comfyui

RUN pip install runpod requests insightface

ADD src/extra_model_paths.yaml ./
WORKDIR /

ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

ADD *snapshot*.json /

RUN /restore_snapshot.sh

CMD ["/start.sh"]

# Stage 2: Download models
FROM base AS downloader

WORKDIR /comfyui

RUN mkdir -p models/checkpoints models/vae models/WAN

RUN wget -O models/WAN/umt5-xxl-enc-bf16.safetensors https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors \
    wget -O models/WAN/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors \
    wget -O models/WAN/Wan2_1_VAE_bf16.safetensors https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors \
    wget -O models/WAN/wan2.1_i2v_480p_14B_bf16.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_480p_14B_bf16.safetensors
# Stage 3: Final image
FROM base AS final

COPY --from=downloader /comfyui/models /comfyui/models

CMD ["/start.sh"]
