# Windows Intel Arc 部署 Breeze TTS 2

给 **Intel Arc（如 A770 Pro）** 用。装 XPU 版 PyTorch，走 eager，**不开 FAST_ALL**。只要能生成音频，不追求实时。

NVIDIA 请用 [../windows/README.md](../windows/README.md)，两套虚拟环境分开（`.venv` / `.venv-intel`），不要混装 CUDA 和 XPU 轮子。

## 准备

1. Windows 10/11 x64，已装较新的 Intel Arc 显卡驱动
2. Python 3.10–3.12（建议 3.12）
3. 显存：eager 约 7.7 GiB，A770 16 GB 够用

## 用法

第一次：双击 `install.bat`，等它跑完，记下窗口里的 `API_KEY`。

之后每次：双击 `start.bat`。出现 `Uvicorn running` 即可用。关窗口或 Ctrl+C 停止。

只合成一条 WAV（不必起 API）：

```powershell
.\.venv-intel\Scripts\python.exe infer.py D:\models\breeze-tts-2 --text "[笑] 你好。" --output outputs\demo.wav
```

声音发虚、发噪时，把 `.env` 里的 `DTYPE` 改成 `float16`，或：

```powershell
.\.venv-intel\Scripts\python.exe infer.py D:\models\breeze-tts-2 --dtype float16 --text "你好。" --output outputs\demo.wav
```

Intel 上一段几秒语音可能要几十秒，属正常。

## 安装脚本会做什么

- 在仓库根目录创建 `.venv-intel`（不碰 NVIDIA 的 `.venv`）
- 从 `https://download.pytorch.org/whl/xpu` 安装 `torch==2.9.1`
- 装 `requirements.txt` 和 `psutil`，**不装 flash-attn / nvidia-ml-py**
- 校验 `torch.xpu.is_available()`
- 生成 `deploy/windows_intel/.env`（`FAST_ALL=false`、`DEVICE=xpu`）

不用 Hugging Face 国内镜像时：

```powershell
powershell -ExecutionPolicy Bypass -File deploy\windows_intel\install.ps1 -SkipHfMirror
```

## 接到 VoStory

- API 地址：`http://127.0.0.1:7860`
- API 密钥：与 `.env` 里的 `API_KEY` 相同
- 最大并发数：1

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `API_KEY` | 安装时生成 | 公网必须设置 |
| `HF_HOME` | `deploy/windows_intel/hf-cache` | 模型缓存 |
| `DEVICE` | `xpu` | 强制走 Intel GPU |
| `DTYPE` | `bfloat16` | 出杂音改 `float16` |
| `FAST_ALL` | `false` | Intel 上不要改成 true |
| `PORT` / `HOST` | `7860` / `0.0.0.0` | 监听 |
| `MODEL_PATH` | 空 | 本地权重目录，优先于 `MODEL_ID` |
| `HF_ENDPOINT` | `https://hf-mirror.com` | 国内镜像；不用则留空 |
