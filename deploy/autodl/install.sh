#!/usr/bin/env bash
# AutoDL 安装：依赖、数据盘缓存目录、.env（不安装 flash-attn）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/autodl/.env"
ENV_EXAMPLE="$ROOT/deploy/autodl/.env.example"
HF_HOME_DEFAULT="/root/autodl-tmp/hf-cache"
PYTHON="${PYTHON:-}"

if [[ -z "$PYTHON" ]]; then
  if [[ -x /root/miniconda3/bin/python ]]; then
    PYTHON=/root/miniconda3/bin/python
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON="$(command -v python3)"
  else
    PYTHON="$(command -v python)"
  fi
fi

echo "[autodl] repo=$ROOT python=$($PYTHON -V 2>&1)"

if ! command -v gcc >/dev/null 2>&1; then
  echo "[autodl] 未找到 gcc，FAST_ALL 预热需要它，尝试安装 build-essential"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends build-essential
  else
    echo "[autodl] 无法自动安装 gcc，请手动安装后再开 FAST_ALL" >&2
  fi
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
else
  echo "[autodl] 警告: 未检测到 nvidia-smi" >&2
fi

"$PYTHON" -m pip install --upgrade pip
"$PYTHON" -m pip install -r "$ROOT/requirements.txt"
"$PYTHON" -m pip install psutil nvidia-ml-py

mkdir -p "$HF_HOME_DEFAULT"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  API_KEY="$("$PYTHON" -c "import secrets; print(secrets.token_urlsafe(24))")"
  # 按显存决定是否默认开启 FAST_ALL（约需 14.4GB）
  FAST_ALL=true
  if command -v nvidia-smi >/dev/null 2>&1; then
    MEM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1 | tr -d ' ')"
    if [[ -n "${MEM_MB:-}" && "$MEM_MB" -lt 20000 ]]; then
      FAST_ALL=false
    fi
  fi
  if [[ "${SKIP_HF_MIRROR:-}" == "1" ]]; then
    HF_ENDPOINT=""
  else
    HF_ENDPOINT="https://hf-mirror.com"
  fi
  "$PYTHON" - "$ENV_FILE" "$API_KEY" "$FAST_ALL" "$HF_ENDPOINT" "$PYTHON" <<'PY'
from pathlib import Path
import sys

path, api_key, fast_all, hf_endpoint, python_bin = (
    Path(sys.argv[1]),
    sys.argv[2],
    sys.argv[3],
    sys.argv[4],
    sys.argv[5],
)
text = path.read_text(encoding="utf-8")
text = text.replace("API_KEY=\n", f"API_KEY={api_key}\n", 1)
text = text.replace("FAST_ALL=true\n", f"FAST_ALL={fast_all}\n", 1)
text = text.replace(
    "HF_ENDPOINT=https://hf-mirror.com\n",
    f"HF_ENDPOINT={hf_endpoint}\n",
    1,
)
text = text.replace("PYTHON=\n", f"PYTHON={python_bin}\n", 1)
path.write_text(text, encoding="utf-8")
print(f"[autodl] 已写入 {path}")
print(f"[autodl] API_KEY={api_key}")
print(f"[autodl] FAST_ALL={fast_all}")
print(f"[autodl] PYTHON={python_bin}")
PY
else
  echo "[autodl] 已存在 $ENV_FILE ，未覆盖"
fi

if [[ "${SKIP_AUTOSTART:-}" == "1" ]]; then
  echo "[autodl] 已跳过开机自启（SKIP_AUTOSTART=1）"
else
  bash "$ROOT/deploy/autodl/enable-autostart.sh"
fi

echo "[autodl] 安装完成。当前启动: bash deploy/autodl/start.sh --tmux"
