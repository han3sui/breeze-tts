"""AutoDL 镜像里 Jupyter / TensorBoard 会先起来，借这次 Python 启动把 Breeze 拉起来。

普通 AutoDL 不跑 cron，crontab @reboot 经常不生效。conda 的 sitecustomize
在系统盘，保存镜像后下次开机仍会执行。serve.py 自己会再 import 一次，这里跳过。
"""

from __future__ import annotations

import os
import subprocess
import sys

_MARKER = "breeze-tts-autodl-sitecustomize"
_SCRIPT = "/root/breeze-tts/deploy/autodl/autodl-onstart.sh"


def _should_start() -> bool:
    if os.environ.get("BREEZE_SKIP_AUTOSTART") == "1":
        return False
    argv0 = os.path.basename(sys.argv[0]) if sys.argv else ""
    if argv0 in {"serve.py", "uvicorn"}:
        return False
    return os.path.isfile(_SCRIPT)


def _start() -> None:
    if not _should_start():
        return
    lock = "/tmp/breeze-tts-autostart.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.write(fd, _MARKER.encode())
        os.close(fd)
    except FileExistsError:
        return
    subprocess.Popen(
        ["/bin/bash", _SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


try:
    _start()
except Exception:
    pass
