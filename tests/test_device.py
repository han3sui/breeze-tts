from types import SimpleNamespace
from unittest.mock import patch

import pytest
import torch

from breeze_infer.device import (
    parse_dtype,
    require_streaming_device,
    supports_fast_path,
)
from breeze_infer.runtime import resolve_device
from models.fast_streaming import FastBreezeStreamingRuntime, FastStreamingConfig


def test_parse_dtype_aliases() -> None:
    assert parse_dtype("bf16") is torch.bfloat16
    assert parse_dtype("float16") is torch.float16


def test_parse_dtype_rejects_unknown() -> None:
    with pytest.raises(ValueError, match="unsupported dtype"):
        parse_dtype("float32")


def test_supports_fast_path_cuda_only() -> None:
    assert supports_fast_path("cuda:0") is True
    assert supports_fast_path("xpu:0") is False
    assert supports_fast_path("cpu") is False


def test_require_streaming_device_rejects_cpu() -> None:
    with pytest.raises(RuntimeError, match="CUDA or Intel XPU"):
        require_streaming_device("cpu")


def test_resolve_device_prefers_explicit() -> None:
    assert resolve_device("xpu:0") == "xpu:0"


def test_resolve_device_falls_back_to_xpu_without_cuda() -> None:
    with (
        patch("breeze_infer.runtime.torch.cuda.is_available", return_value=False),
        patch("breeze_infer.runtime.is_xpu_available", return_value=True),
    ):
        assert resolve_device() == "xpu:0"


def test_xpu_runtime_forces_eager(monkeypatch) -> None:
    model = SimpleNamespace(
        config=SimpleNamespace(
            codec_config=SimpleNamespace(codebook_size=8, sampling_rate=24000),
            vocab_size=16,
        )
    )
    monkeypatch.setattr(
        "models.fast_streaming._get_device", lambda _model: SimpleNamespace(type="xpu")
    )
    monkeypatch.setattr(
        "models.fast_streaming._get_dtype", lambda _model: torch.bfloat16
    )

    runtime = FastBreezeStreamingRuntime(
        model, object(), FastStreamingConfig(fast_all=True)
    )

    assert runtime.fast_enabled is False
    assert runtime.codec_chunk_frames == 2
    assert model._fast_text_encoder_cudagraph is False
