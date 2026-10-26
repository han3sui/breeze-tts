"""部署镜像构建期校验：只检查 serve.py 实际依赖，不要求 flash-attn。"""

from __future__ import annotations

import importlib.metadata
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

import qwen_tts
import torch
import transformers

from models.fast_streaming import FastStreamingConfig
from models.warmup_profile import load_warmup_profile

EXPECTED = {
    "torch": "2.9.1",
    "transformers": "4.57.3",
    "qwen-tts": "0.1.1",
}


def main() -> None:
    if not all((qwen_tts, torch, transformers)):
        raise RuntimeError("one or more required modules failed to import")
    versions = {name: importlib.metadata.version(name) for name in EXPECTED}
    for name, expected in EXPECTED.items():
        actual = versions[name].split("+")[0]
        if actual != expected:
            raise RuntimeError(f"{name}: expected {expected}, got {versions[name]}")

    cfg = FastStreamingConfig(fast_all=True)
    if not cfg.fast_all:
        raise RuntimeError("fast runtime configuration is unavailable")

    load_warmup_profile(REPO_ROOT / "configs/fast.json")

    print("Deploy image smoke check passed:", versions)


if __name__ == "__main__":
    main()
