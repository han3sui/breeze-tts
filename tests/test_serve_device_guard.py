from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "deploy"))

from serve import _is_fatal_device_error  # noqa: E402


def test_detects_xpu_native_api_unknown() -> None:
    err = RuntimeError(
        "Native API failed. Native API returns: 2147483646 (UR_RESULT_ERROR_UNKNOWN)"
    )
    assert _is_fatal_device_error(err)


def test_detects_device_lost() -> None:
    assert _is_fatal_device_error(RuntimeError("UR_RESULT_ERROR_DEVICE_LOST"))


def test_ignores_ordinary_runtime_error() -> None:
    assert not _is_fatal_device_error(ValueError("missing template fields"))
    assert not _is_fatal_device_error(RuntimeError("ref audio is empty"))
