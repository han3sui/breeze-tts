#!/usr/bin/env bash
# AutoDL 启动 serve.py；加 --tmux 可在断开 SSH 后继续运行
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/autodl/.env"
PYTHON="${PYTHON:-}"
USE_TMUX=0

if [[ "${1:-}" == "--tmux" ]]; then
  USE_TMUX=1
fi

if [[ -z "$PYTHON" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
  else
    PYTHON=python
  fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[autodl] 缺少 $ENV_FILE ，请先执行 bash deploy/autodl/install.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${API_KEY:-}" ]]; then
  echo "[autodl] 警告: API_KEY 为空，接口不鉴权" >&2
fi

export API_KEY MODEL_ID MODEL_REVISION HF_TOKEN HF_HOME FAST_ALL HOST PORT
export HF_ENDPOINT="${HF_ENDPOINT:-}"
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"

mkdir -p "${HF_HOME:-/root/autodl-tmp/hf-cache}"

cd "$ROOT"
CMD=("$PYTHON" deploy/serve.py)

if [[ "$USE_TMUX" -eq 1 ]]; then
  if ! command -v tmux >/dev/null 2>&1; then
    echo "[autodl] 未安装 tmux，改为前台启动" >&2
    exec "${CMD[@]}"
  fi
  SESSION="${TMUX_SESSION:-breeze-tts}"
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[autodl] tmux 会话 $SESSION 已在运行，执行: tmux attach -t $SESSION"
    exit 0
  fi
  # 新会话里重新 source，避免 tmux 吃掉当前环境变量
  tmux new-session -d -s "$SESSION" \
    bash -lc "set -a; source '$ENV_FILE'; set +a; export CC='${CC:-gcc}' CXX='${CXX:-g++}'; cd '$ROOT'; exec '$PYTHON' deploy/serve.py"
  echo "[autodl] 已在 tmux 会话 $SESSION 中启动，查看: tmux attach -t $SESSION"
  exit 0
fi

exec "${CMD[@]}"
