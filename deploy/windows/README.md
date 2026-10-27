# Windows 本地部署 Breeze TTS 2

在本机用 NVIDIA 显卡跑 `deploy/serve.py`。接口、鉴权、环境变量与 [deploy/README.md](../README.md) 相同。不装 `flash-attn`，走 eager + SDPA / CUDA Graph。

Intel Arc（A770 等）请用 [../windows_intel/README.md](../windows_intel/README.md)，不要和这套 CUDA 环境混装。

## 准备

1. Windows 10/11 x64，已装较新的 NVIDIA 驱动（`nvidia-smi` 能跑）
2. Python 3.10–3.12（建议 3.12）
3. 显存：eager 约 7.7 GiB（建议 12 GB）；`FAST_ALL=true` 约 14.4 GiB（建议 24 GB）

## 用法

第一次：双击 `install.bat`，等它跑完，记下窗口里的 `API_KEY`。

之后每次：双击 `start.bat`。出现 `Uvicorn running on http://0.0.0.0:7860` 即可用。关窗口或 Ctrl+C 停止。

首次启动会下载权重；`FAST_ALL=true` 时还有 CUDA Graph 预热，可能要几分钟。加载中 `GET /health` 返回 503 是正常的。

## 安装脚本会做什么

- 在仓库根目录创建 `.venv`（已有则复用）
- 从 `https://download.pytorch.org/whl/cu128` 安装 `torch==2.9.1`，再装 `requirements.txt` 和 `psutil` / `nvidia-ml-py`
- **不装 flash-attn**
- 校验 `torch.cuda.is_available()`
- 生成 `deploy/windows/.env`（已存在则不覆盖）
- 按显存决定默认 `FAST_ALL`（低于约 20 GB 设为 `false`）
- 国内拉 Hugging Face 默认走 `https://hf-mirror.com`

需要改参数时再在 PowerShell 里跑：

```powershell
powershell -ExecutionPolicy Bypass -File deploy\windows\install.ps1 -SkipHfMirror
powershell -ExecutionPolicy Bypass -File deploy\windows\install.ps1 -TorchIndexUrl https://download.pytorch.org/whl/cu126
```

编辑 `deploy/windows/.env`：可改 `API_KEY`、`FAST_ALL`、`MODEL_PATH`（已有本地下载的权重时填写）。

## 接到 VoStory

- API 地址：`http://127.0.0.1:7860`
- API 密钥：与 `.env` 里的 `API_KEY` 相同
- 最大并发数：1

局域网或公网需要自己做端口转发 / 反代；公网必须设置 `API_KEY`。

## 环境变量

`deploy/windows/.env` 由 `start.bat` 加载：

| 变量 | Windows 默认 | 说明 |
|---|---|---|
| `API_KEY` | 安装时生成 | 公网必须设置 |
| `HF_HOME` | `deploy/windows/hf-cache` | 模型缓存 |
| `PORT` | `7860` | 监听端口 |
| `HOST` | `0.0.0.0` | 只本机访问可改 `127.0.0.1` |
| `FAST_ALL` | 按显存推断 | 约 14.4GB；不足则 `false` |
| `MODEL_ID` | `BreezeBlue/Breeze-TTS-2` | Hugging Face 仓库 |
| `MODEL_PATH` | 空 | 本地权重目录，优先于 `MODEL_ID` |
| `HF_ENDPOINT` | `https://hf-mirror.com` | 国内镜像；不用则留空 |
| `HF_TOKEN` | 空 | 模型页需要同意许可时填写 |
| `PYTHON` | 安装时写入绝对路径 | 指向 `.venv\Scripts\python.exe` |
| `TORCHDYNAMO_DISABLE` | `1` | 避免 inductor 预热失败 |

## 不要做的事

- 不要安装 flash-attn
- 不要只执行 `pip install -r requirements.txt`（Windows 上容易装成 CPU 版 torch）
- 不要在 16GB 及以下显卡上开 `FAST_ALL=true`
- 不要把未设 `API_KEY` 的服务暴露到公网
