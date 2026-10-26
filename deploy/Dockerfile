# Breeze TTS 2 API 镜像（runtime-only）
# serve.py 使用 eager + SDPA / CUDA Graph，不依赖 flash-attn，避免 GitHub Actions 源码编译
# 模型权重不打进镜像，首次启动时下载到 HF_HOME（RunPod 上挂载 Network Volume 到 /workspace 即可复用）

ARG PYTORCH_TAG=2.9.1-cuda12.8-cudnn9

FROM pytorch/pytorch:${PYTORCH_TAG}-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    TOKENIZERS_PARALLELISM=false \
    HF_HOME=/workspace/hf-cache \
    MODEL_ID=BreezeBlue/Breeze-TTS-2 \
    FAST_ALL=true \
    HOST=0.0.0.0 \
    PORT=7860 \
    CC=gcc \
    CXX=g++

# sox/ffmpeg 供音频；build-essential 供 FAST_ALL 预热时 Triton/Inductor 即时编译（不是 flash-attn）
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        libsndfile1 \
        sox \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/breeze-infer

COPY requirements.txt ./

RUN python -m pip install --upgrade pip \
    && python -m pip install -r requirements.txt \
    && python -m pip install psutil nvidia-ml-py

COPY . .

# 构建期校验 serve 路径依赖（不含 flash-attn）
RUN python deploy/smoke_check.py

EXPOSE 7860

CMD ["python", "deploy/serve.py"]
