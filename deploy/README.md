# Breeze TTS 2 部署（Docker / RunPod）

在上游 `breeze_infer.api` 外层包了一层 `deploy/serve.py`，不改上游代码：

- **Bearer 鉴权**：设置 `API_KEY` 后，除 `/health` 外的接口都需要 `Authorization: Bearer <API_KEY>`
- **`/status`**：返回 CPU / 内存 / GPU 负载，字段与 VoStory「TTS 提供商 → 系统负载」一致
- **环境变量配置**：模型、加速开关、端口都从环境变量读取，方便 RunPod 模板填写

| 接口 | 鉴权 | 说明 |
|------|------|------|
| `POST /v1/audio/speech` | 是 | 合成，返回 24kHz 单声道 s16le PCM 流 |
| `POST /v1/audio/speech/batch` | 是 | 批量合成 |
| `GET /v1/model` | 是 | 模型信息（VoStory「测试」按钮调用） |
| `GET /status` | 是 | 系统负载 |
| `GET /health` | 否 | 加载中返回 503，就绪返回 200 |

服务是**单并发**的：已有请求在跑时返回 409，VoStory 中该提供商的最大并发数保持 1。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `API_KEY` | 空 | 鉴权密钥，**公网部署必须设置** |
| `MODEL_ID` | `BreezeBlue/Breeze-TTS-2` | Hugging Face 仓库名，首次启动下载到 `HF_HOME` |
| `MODEL_PATH` | 空 | 本地模型目录，设置后优先于 `MODEL_ID` |
| `MODEL_REVISION` | 空 | Hugging Face 版本 |
| `HF_TOKEN` | 空 | 模型页需要同意许可时填写 |
| `HF_HOME` | `/workspace/hf-cache` | 模型缓存目录 |
| `FAST_ALL` | `true` | 全部加速路径（CUDA Graph），约 14.4GB 显存；16GB 以下显卡设为 `false` |
| `HOST` / `PORT` | `0.0.0.0` / `7860` | 监听地址 |

## 镜像构建与发布

推送 `v*` 标签时，GitHub Actions（`.github/workflows/docker-publish.yml`）自动构建并推送：

```
<DOCKERHUB_USERNAME>/breeze-tts:<tag>
<DOCKERHUB_USERNAME>/breeze-tts:latest
```

需要在仓库 Settings → Secrets and variables → Actions 中配置 `DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`。也可以在 Actions 页面手动触发（标签为 `sha-<commit>`）。

部署镜像基于 PyTorch CUDA **runtime**，不编译、不安装 `flash-attn`。`deploy/serve.py` 使用 eager + SDPA / CUDA Graph，`FAST_ALL` 不依赖 FlashAttention。镜像内装了 `gcc`（`build-essential`），供 `FAST_ALL` 预热时 Triton/Inductor 即时编译；没有编译器时启动会报 `Failed to find C compiler`。

上游官方镜像（`docker/Dockerfile`）仍会从源码编译 flash-attn，只用于官方推理实验；**不要**把它的产物接到这份 compose / RunPod 模板上。

## RunPod 部署

RunPod 的 Pod 不支持 docker-compose，用模板（Template）部署：

1. **Network Volume**：在 RunPod 创建一个 Network Volume（30GB 足够），与 Pod 选同一数据中心。Pod 会把它挂载到 `/workspace`，模型下载一次后复用。
2. **新建模板**（Templates → New Template）：
   - Container Image：`han3sui/breeze-tts:latest`（或固定版本号）
   - Container Disk：30GB
   - Volume Mount Path：`/workspace`
   - Expose HTTP Ports：`7860`
   - Environment Variables：
     - `API_KEY` = 自己生成的随机串（建议用 RunPod Secrets 引用）
     - `FAST_ALL` = `true`（24GB 显存的 4090 可开；16GB 以下显卡填 `false`）
     - `HF_TOKEN` = 需要时填写
   - Container Start Command：留空（使用镜像默认的 `python deploy/serve.py`）
3. **部署 Pod**：选 RTX 4090（Community Cloud 便宜，Secure Cloud 稳定），挂上 Network Volume。首次启动会下载权重并做加速预热，日志出现 `Uvicorn running on http://0.0.0.0:7860` 后可用。
4. **在 VoStory 中配置**「AI 配置 → TTS 提供商」：
   - API 地址：`https://<pod-id>-7860.proxy.runpod.net`
   - API 密钥：与 `API_KEY` 相同
   - 最大并发数：1
   - 点击「测试」应显示模型摘要，「查看状态」可看到 GPU 负载

用完及时 Stop Pod；模型在 Network Volume 上，下次启动无需重新下载。

## 本地 / 普通 GPU 服务器

```bash
cd deploy
cp .env.example .env    # 修改 API_KEY
docker compose up -d            # 使用已发布镜像
docker compose up -d --build    # 或本地构建
```

模型缓存在 `deploy/hf-cache/`。需要宿主机安装 NVIDIA 驱动与 NVIDIA Container Toolkit。

## 许可

上游源码为 Apache 2.0；Breeze TTS 2 模型权重、衍生模型与自部署产出仅限研究与非商业用途。镜像不包含模型权重。
