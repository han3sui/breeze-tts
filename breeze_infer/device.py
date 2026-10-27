"""CUDA / Intel XPU helpers so eager inference can share one code path."""

from __future__ import annotations

import torch

_DTYPE_ALIASES = {
    "bfloat16": torch.bfloat16,
    "bf16": torch.bfloat16,
    "float16": torch.float16,
    "fp16": torch.float16,
    "half": torch.float16,
}

STREAMING_DEVICE_TYPES = frozenset({"cuda", "xpu"})


def device_type(device: torch.device | str) -> str:
    if isinstance(device, str):
        return device.split(":", 1)[0]
    return device.type


def xpu_module():
    return getattr(torch, "xpu", None)


def is_xpu_available() -> bool:
    xpu = xpu_module()
    return xpu is not None and bool(xpu.is_available())


def parse_dtype(name: str) -> torch.dtype:
    key = name.strip().lower()
    if key not in _DTYPE_ALIASES:
        raise ValueError(f"unsupported dtype {name!r}; use bfloat16 or float16")
    return _DTYPE_ALIASES[key]


def supports_fast_path(device: torch.device | str) -> bool:
    return device_type(device) == "cuda"


def require_streaming_device(device: torch.device | str) -> None:
    kind = device_type(device)
    if kind not in STREAMING_DEVICE_TYPES:
        raise RuntimeError(
            f"streaming requires a CUDA or Intel XPU device, got {device}"
        )


def set_accelerator_device(device: str) -> None:
    if device in {"cuda", "xpu"}:
        device = f"{device}:0"
    if device.startswith("cuda"):
        torch.cuda.set_device(device)
        return
    if device.startswith("xpu"):
        xpu = xpu_module()
        if xpu is None:
            raise RuntimeError("this PyTorch build has no torch.xpu")
        xpu.set_device(device)


def seed_accelerator(seed: int) -> None:
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    xpu = xpu_module()
    if xpu is not None and xpu.is_available() and hasattr(xpu, "manual_seed_all"):
        xpu.manual_seed_all(seed)


def synchronize(device: str | torch.device | None = None) -> None:
    if device is None:
        if torch.cuda.is_available():
            torch.cuda.synchronize()
        if is_xpu_available():
            torch.xpu.synchronize()
        return
    dev = torch.device(device)
    if dev.type == "cuda":
        torch.cuda.synchronize(dev)
    elif dev.type == "xpu" and is_xpu_available():
        torch.xpu.synchronize(dev)


def timing_events(device: torch.device):
    """CUDA Event pair for optional timing; other devices skip it."""
    if device.type != "cuda":
        return None, None
    start = torch.cuda.Event(enable_timing=True)
    end = torch.cuda.Event(enable_timing=True)
    return start, end
