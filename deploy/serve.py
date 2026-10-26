"""Breeze TTS 部署入口：在上游 breeze_infer.api 外层加 Bearer 鉴权与 /status，不修改上游代码。

启动参数默认从环境变量读取（便于 Docker / RunPod 模板配置）；命令行显式传参时原样交给上游 main()。

环境变量：
    API_KEY         Bearer 鉴权密钥，为空时不鉴权（会打印警告）
    MODEL_ID        Hugging Face 仓库名，默认 BreezeBlue/Breeze-TTS-2，首次启动自动下载到 HF_HOME
    MODEL_PATH      本地模型目录，设置后优先于 MODEL_ID
    MODEL_REVISION  Hugging Face 版本（仅对 MODEL_ID 生效）
    FAST_ALL        是否开启全部加速路径（CUDA Graph），默认 true，约需 14.4GB 显存
    HOST / PORT     监听地址，默认 0.0.0.0:7860
"""

from __future__ import annotations

import hmac
import os
import platform
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

import psutil  # noqa: E402
import torch  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from starlette.types import ASGIApp, Receive, Scope, Send  # noqa: E402

from breeze_infer import api  # noqa: E402

API_KEY = os.environ.get("API_KEY", "").strip()
# /health 免鉴权，供负载均衡与人工检查服务是否在线
PUBLIC_PATHS = frozenset({"/health"})


class BearerAuthMiddleware:
    """纯 ASGI 中间件：不包装响应体，保留上游流式响应与客户端断开时的资源释放逻辑。"""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app
        self.expected = API_KEY.encode()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or not self.expected or scope["path"] in PUBLIC_PATHS:
            await self.app(scope, receive, send)
            return

        auth = b""
        for name, value in scope.get("headers", []):
            if name == b"authorization":
                auth = value
                break
        scheme, _, token = auth.partition(b" ")
        if scheme.lower() != b"bearer" or not hmac.compare_digest(token.strip(), self.expected):
            response = JSONResponse(
                {"detail": "Invalid or missing API key"},
                status_code=401,
                headers={"WWW-Authenticate": "Bearer"},
            )
            await response(scope, receive, send)
            return

        await self.app(scope, receive, send)


def _read_text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def _read_int(path: str) -> int | None:
    text = _read_text(path)
    if text is None:
        return None
    try:
        return int(text)
    except ValueError:
        return None


def _in_container() -> bool:
    return os.path.exists("/.dockerenv") or os.path.exists("/run/.containerenv")


def _cpu_model() -> str:
    cpuinfo = _read_text("/proc/cpuinfo")
    if cpuinfo:
        for line in cpuinfo.splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    return platform.processor() or "Unknown"


def _cgroup_cpu_cores() -> float | None:
    """容器实际分配的 CPU 核数（cgroup v2 优先，回退 v1），未限制时返回 None"""
    cpu_max = _read_text("/sys/fs/cgroup/cpu.max")
    if cpu_max:
        parts = cpu_max.split()
        if len(parts) == 2 and parts[0] != "max":
            return int(parts[0]) / int(parts[1])
    quota = _read_int("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")
    period = _read_int("/sys/fs/cgroup/cpu/cpu.cfs_period_us")
    if quota and quota > 0 and period and period > 0:
        return quota / period
    return None


def _cgroup_memory() -> tuple[int, int] | None:
    """容器内存限制与用量（cgroup v2 优先，回退 v1），未限制时返回 None"""
    host_total = psutil.virtual_memory().total
    for limit_path, usage_path in (
        ("/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory.current"),
        ("/sys/fs/cgroup/memory/memory.limit_in_bytes", "/sys/fs/cgroup/memory/memory.usage_in_bytes"),
    ):
        limit = _read_int(limit_path)
        usage = _read_int(usage_path)
        if limit and usage is not None and limit <= host_total:
            return limit, usage
    return None


def _cpu_info() -> dict:
    physical = psutil.cpu_count(logical=False)
    logical = psutil.cpu_count(logical=True)
    cores = _cgroup_cpu_cores() if _in_container() else None
    if cores:
        logical = max(1, round(cores))
        physical = logical
    return {
        "name": _cpu_model(),
        "percent": psutil.cpu_percent(interval=0.5),
        "count_physical": physical,
        "count_logical": logical,
    }


def _memory_info() -> dict:
    cg = _cgroup_memory() if _in_container() else None
    if cg:
        total, used = cg
        percent = round(used / total * 100, 1) if total else 0
    else:
        mem = psutil.virtual_memory()
        total, used, percent = mem.total, mem.used, mem.percent
    return {
        "total_mb": round(total / 1024 / 1024),
        "used_mb": round(used / 1024 / 1024),
        "percent": percent,
    }


def _gpu_info() -> dict | None:
    if not torch.cuda.is_available():
        return None
    dev = torch.cuda.current_device()
    torch_total = torch.cuda.get_device_properties(dev).total_memory
    gpu_util = None
    used_bytes = None
    total_bytes = None
    try:
        import pynvml

        pynvml.nvmlInit()
        try:
            handle = pynvml.nvmlDeviceGetHandleByIndex(dev)
            gpu_util = pynvml.nvmlDeviceGetUtilizationRates(handle).gpu
            # 与 nvidia-smi 同源：整卡被占显存，不是 PyTorch allocated
            mem = pynvml.nvmlDeviceGetMemoryInfo(handle)
            used_bytes = int(mem.used)
            total_bytes = int(mem.total)
        finally:
            pynvml.nvmlShutdown()
    except Exception:
        pass
    total = total_bytes if total_bytes else torch_total
    used = used_bytes if used_bytes is not None else torch.cuda.memory_reserved(dev)
    return {
        "name": torch.cuda.get_device_name(dev),
        "gpu_utilization": gpu_util,
        "memory_total_mb": round(total / 1024 / 1024),
        "memory_used_mb": round(used / 1024 / 1024),
        "memory_allocated_mb": round(torch.cuda.memory_allocated(dev) / 1024 / 1024),
        "memory_reserved_mb": round(torch.cuda.memory_reserved(dev) / 1024 / 1024),
    }


@api.app.get("/status")
def status() -> dict:
    """系统负载（字段与 VoStory TTS 提供商「系统负载」列一致）"""
    return {"cpu": _cpu_info(), "memory": _memory_info(), "gpu": _gpu_info()}


api.app.add_middleware(BearerAuthMiddleware)


def _env_flag(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _argv_from_env() -> list[str]:
    model = os.environ.get("MODEL_PATH", "").strip() or os.environ.get("MODEL_ID", "").strip()
    argv = [
        model or "BreezeBlue/Breeze-TTS-2",
        "--host",
        os.environ.get("HOST", "0.0.0.0"),
        "--port",
        os.environ.get("PORT", "7860"),
    ]
    revision = os.environ.get("MODEL_REVISION", "").strip()
    if revision:
        argv += ["--revision", revision]
    if _env_flag("FAST_ALL", True):
        argv.append("--fast-all")
    return argv


def main() -> None:
    if not API_KEY:
        print("[serve] WARNING: API_KEY 未设置，接口不鉴权，切勿暴露到公网", file=sys.stderr, flush=True)
    if len(sys.argv) == 1:
        sys.argv = [sys.argv[0], *_argv_from_env()]
    print(f"[serve] starting breeze_infer.api {' '.join(sys.argv[1:])}", flush=True)
    api.main()


if __name__ == "__main__":
    main()
