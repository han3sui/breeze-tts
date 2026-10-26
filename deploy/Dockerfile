# Breeze TTS 2 API 镜像（两阶段构建）
#   阶段一：在 devel 镜像中编译 flash-attn wheel（需要 nvcc，不需要 GPU）
#   阶段二：在 runtime 镜像中安装依赖与 wheel，体积更小
# 模型权重不打进镜像，首次启动时下载到 HF_HOME（RunPod 上挂载 Network Volume 到 /workspace 即可复用）

ARG PYTORCH_TAG=2.9.1-cuda12.8-cudnn9

# ===== 阶段一：编译 flash-attn =====
FROM pytorch/pytorch:${PYTORCH_TAG}-devel AS builder

# flash-attn 2.8.3 只识别 80/90/100/120 几档：80 覆盖 A100/3090/A5000/4090/L4/L40S，90 覆盖 H100
ARG FLASH_ATTN_CUDA_ARCHS="80;90"
# 并行编译数，越大越快但越吃内存（每个任务约 4~8GB）
ARG MAX_JOBS=4

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git ninja-build \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt ./

# 优先下载与 torch/CUDA/Python 匹配的官方预编译 wheel，没有时才从源码编译
RUN python -m pip install --upgrade pip setuptools wheel packaging ninja \
    && python -m pip install -r requirements.txt \
    && MAX_JOBS=${MAX_JOBS} FLASH_ATTN_CUDA_ARCHS="${FLASH_ATTN_CUDA_ARCHS}" python -m pip wheel \
        --no-build-isolation \
        --no-deps \
        -w /wheels \
        "flash-attn==2.8.3"

# ===== 阶段二：运行镜像 =====
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
    PORT=7860

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg libsndfile1 sox \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/breeze-infer

COPY requirements.txt ./
COPY --from=builder /wheels /tmp/wheels

RUN python -m pip install --upgrade pip \
    && python -m pip install -r requirements.txt \
    && python -m pip install --no-deps /tmp/wheels/*.whl \
    && python -m pip install psutil nvidia-ml-py \
    && rm -rf /tmp/wheels

COPY . .

# 构建期校验依赖版本与 flash-attn 可导入
RUN python docker/smoke_check.py

EXPOSE 7860

CMD ["python", "deploy/serve.py"]
