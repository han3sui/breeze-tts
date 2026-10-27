# AutoDL 部署 Breeze TTS 2

普通 AutoDL 实例**不能再跑 Docker**，也不能导入 `han3sui/breeze-tts` 镜像。平台用容器隔离资源，实例内没有 Docker 守护进程；需要 Docker 只能租裸金属。

因此 AutoDL 上把机器当成预装 CUDA 的 Linux：SSH 装依赖，用 `deploy/serve.py` 启动。接口、鉴权、环境变量与 [deploy/README.md](../deploy/README.md) 相同，差别只在路径和端口。

## 和 Runpod 的差别

| | Runpod | AutoDL 普通实例 |
|---|---|---|
| 部署方式 | 拉 Docker 镜像 | SSH 装 Python 依赖 |
| 公网入口 | HTTP 端口可自选（默认 7860） | 只映射 **6006 / 6008**（自定义服务） |
| 模型缓存 | Volume → `/workspace/hf-cache` | 系统盘 **`/root/hf-cache`**（保存镜像会带走） |
| 环境复用 | 镜像本身 | 关机后「保存镜像」（只含系统盘） |
| 开机自启 | 镜像 CMD | Jupyter 一启动就跑 sitecustomize 拉起 `start.sh --tmux`（crontab 作备份） |

仓库和权重都放系统盘：`/root/breeze-tts` + `/root/hf-cache`（约 8GB）。系统盘约 30GB，装 conda 包和模型够用。数据盘 `/root/autodl-tmp` **不会**打进镜像，不要把缓存放到那里。

AutoDL 不能拉 Docker 镜像，**必须先把仓库 clone 到实例里**，再跑安装脚本。第一次 SSH 进去复制下面整段即可（仓库地址换成你的）：

```bash
cd /root
git clone https://github.com/han3sui/breeze-tts.git
cd breeze-tts
bash deploy/autodl/install.sh
# 记下输出里的 API_KEY，给 VoStory 用
bash deploy/autodl/start.sh --tmux
```

`install.sh` 只装依赖和注册开机自启，**不会立刻启动服务**，所以还要执行 `start.sh --tmux`。等到日志出现 `Uvicorn running on http://0.0.0.0:6006`。

## 1. 开实例

1. 镜像尽量选 **PyTorch 2.9 + CUDA 12.8** 的社区镜像；对不上脚本会再装 `torch==2.9.1`。
2. GPU：4090 / 24GB 才能开 `FAST_ALL=true`；16GB 及以下设 `false`。
3. 系统盘 30GB 即可（权重约 8GB）；数据盘可按需，不参与镜像。
4. 用 SSH 或 Jupyter 终端进入实例。

## 2. 安装

代码已在系统盘时（例如上次 clone 过），进入仓库再装即可：

```bash
cd /root/breeze-tts
bash deploy/autodl/install.sh
```

脚本会：

- 检查 GPU / `gcc`（没有则尝试安装 `build-essential`，供 `FAST_ALL` 预热）
- `pip install -r requirements.txt` 以及 `psutil`、`nvidia-ml-py`（**不装 flash-attn**）
- 创建 `/root/hf-cache`
- 生成 `deploy/autodl/.env`（已存在则不覆盖）
- 注册开机自启（不要时加 `SKIP_AUTOSTART=1`）

国内拉 Hugging Face 默认走 `https://hf-mirror.com`。不用镜像时：

```bash
SKIP_HF_MIRROR=1 bash deploy/autodl/install.sh
```

编辑 `deploy/autodl/.env`：把 `API_KEY` 改成自己的随机串（安装时若为空会自动生成一串，记下来给 VoStory 用）。

## 3. 启动与看门狗

默认带看门狗：`serve.py` 退出后隔 `WATCH_DELAY` 秒（默认 5）再拉起。

```bash
bash deploy/autodl/start.sh            # 前台 + 看门狗
bash deploy/autodl/start.sh --tmux     # tmux 后台 + 看门狗（推荐）
bash deploy/autodl/start.sh --once     # 只跑一次，方便看报错
```

日志出现 `Uvicorn running on http://0.0.0.0:6006` 后再测。首次会下载权重；`FAST_ALL=true` 时还有 CUDA Graph 预热，可能要几分钟。加载中 `GET /health` 返回 503 是正常的。

默认监听 **6006**，才能走 AutoDL 自定义服务。不要用 7860。

看日志：`tmux attach -t breeze-tts`（Ctrl+B 再 D 断开，不关进程）。

## 4. 开机自启

`install.sh` 默认执行 `deploy/autodl/enable-autostart.sh`。AutoDL 普通实例**通常不跑 cron**，只写 crontab 开机不会起来。脚本会同时挂三处（都在系统盘，保存镜像会带走）：

1. conda `sitecustomize.py`：平台一开机就会拉 Jupyter，借这次 Python 启动执行 `autodl-onstart.sh`
2. crontab `@reboot`：若镜像后来自己启了 cron，也能用
3. `/etc/profile.d/breeze-tts-autostart.sh`：SSH / 登录 shell 兜底

```bash
bash deploy/autodl/enable-autostart.sh        # 重新注册
bash deploy/autodl/enable-autostart.sh --off  # 取消
```

控制台「启动脚本」也可以填（不依赖上面三项）：

```bash
bash /root/breeze-tts/deploy/autodl/autodl-onstart.sh
```

换仓库目录后重新执行一次 `enable-autostart.sh`。`FAST_ALL` 预热会关掉 torch dynamo，并且跳过 `cudagraph_mark_step_begin`（避免 2.9.1 inductor `duplicate template name`），原生 CUDA Graph 仍开启。

## 5. 接到 VoStory

1. 控制台 → 该实例 → **自定义服务**，复制 **6006** 对应的 HTTPS，例如 `https://xxxx.nmb2.seetacloud.com:8443`。
2. VoStory「AI 配置 → TTS 提供商」：
   - API 地址：上面这个地址（不要再拼 `:7860`）
   - API 密钥：与 `.env` 里的 `API_KEY` 相同
   - 最大并发数：1

开放任意端口需要企业认证；**6006 / 6008 自定义服务**一般实例可用。未认证的个人账号如果没有自定义服务，只能 SSH 隧道，VoStory 从外网连不上。

## 6. 保存镜像与换机

装好依赖后关机 → 更多操作 → **保存镜像**。下次开同地区实例选这份镜像：conda 包、仓库、`/root/hf-cache`、开机自启钩子都会在，不用重装 pip，也不用重新下模型。

保存镜像**只含系统盘**。`/root/autodl-tmp` 在数据盘上，换机器是空的，所以权重必须放 `/root/hf-cache`。新机器的公网 6006 地址会变，VoStory 里改一下即可。

同一实例关机再开：sitecustomize 会再拉 `start.sh --tmux`。若自启没挂上，再跑一次 `enable-autostart.sh`。

## 7. 弹性部署（可选）

环境已经打进「已保存镜像」后，可用 ReplicaSet。启动命令必须前台运行（不要 `&`，命令结束容器会停）。前台默认带看门狗：

```bash
cd /root/breeze-tts && bash deploy/autodl/start.sh
```

第一次建议仍 SSH 手动跑通，再改成启动命令。

## 环境变量

`deploy/autodl/.env` 由 `start.sh` 加载，含义与部署入口一致：

| 变量 | AutoDL 默认 | 说明 |
|------|-------------|------|
| `API_KEY` | 安装时生成 | 公网必须设置 |
| `HF_HOME` | `/root/hf-cache` | 模型缓存，放系统盘以便保存镜像带走 |
| `PORT` | `6006` | 自定义服务映射端口 |
| `HOST` | `0.0.0.0` | 监听地址 |
| `FAST_ALL` | 按显存推断 | 约 14.4GB；不足则 `false` |
| `MODEL_ID` | `BreezeBlue/Breeze-TTS-2` | Hugging Face 仓库 |
| `HF_ENDPOINT` | `https://hf-mirror.com` | 国内镜像；不用则留空 |
| `HF_TOKEN` | 空 | 模型页需要同意许可时填写 |
| `WATCH_DELAY` | `5` | 看门狗重启间隔（秒） |
| `PYTHON` | 安装时写入绝对路径 | crontab / tmux 里避免找不到 conda python |

## 不要做的事

- 不要在实例里 `docker pull` / `docker compose`。
- 不要监听 7860（外网到不了）。
- 不要把 `HF_HOME` 放到 `/root/autodl-tmp`（数据盘不进镜像）。
- 不要安装 flash-attn；`serve.py` 走 eager + SDPA / CUDA Graph。
- 不要以为保存镜像会带上数据盘上的任何文件。
