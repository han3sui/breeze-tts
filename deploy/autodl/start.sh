#!/usr/bin/env bash
# AutoDL 启动 serve.py。默认带看门狗（崩溃后重启）；--once 只跑一次；--tmux 放到后台会话
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/autodl/.env"
PYTHON="${PYTHON:-}"
USE_TMUX=0
MODE=watch

for arg in "$@"; do
  case "$arg" in
    --tmux) USE_TMUX=1 ;;
    --once) MODE=once ;;
    --watch) MODE=watch ;;
    *)
      echo "用法: bash deploy/autodl/start.sh [--tmux] [--watch|--once]" >&2
      exit 1
      ;;
  esac
done

resolve_python() {
  if [[ -n "$PYTHON" ]]; then
    if [[ -x "$PYTHON" ]]; then
      return
    fi
    if command -v "$PYTHON" >/dev/null 2>&1; then
      PYTHON="$(command -v "$PYTHON")"
      return
    fi
  fi
  local candidate
  for candidate in \
    /root/miniconda3/bin/python \
    /root/miniconda3/bin/python3 \
    "$(command -v python3 || true)" \
    "$(command -v python || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      PYTHON="$candidate"
      return
    fi
  done
  echo "[autodl] 未找到 python" >&2
  exit 1
}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[autodl] 缺少 $ENV_FILE ，请先执行 bash deploy/autodl/install.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

resolve_python

if [[ -z "${API_KEY:-}" ]]; then
  echo "[autodl] 警告: API_KEY 为空，接口不鉴权" >&2
fi

export API_KEY MODEL_ID MODEL_REVISION HF_TOKEN HF_HOME FAST_ALL HOST PORT
export HF_ENDPOINT="${HF_ENDPOINT:-}"
export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"
export PYTHON

WATCH_DELAY="${WATCH_DELAY:-5}"
mkdir -p "${HF_HOME:-/root/autodl-tmp/hf-cache}"
cd "$ROOT"

run_once() {
  echo "[autodl] starting: $PYTHON deploy/serve.py"
  "$PYTHON" deploy/serve.py
}

run_watch() {
  # Ctrl+C / SIGTERM 时退出循环，避免杀不掉
  trap 'echo "[autodl] 收到退出信号"; exit 0' INT TERM
  while true; do
    run_once || true
    echo "[autodl] 进程退出，${WATCH_DELAY}s 后重启（调试可加 --once）"
    sleep "$WATCH_DELAY"
  done
}

run_server() {
  if [[ "$MODE" == "once" ]]; then
    run_once
  else
    run_watch
  fi
}

if [[ "$USE_TMUX" -eq 1 ]]; then
  if ! command -v tmux >/dev/null 2>&1; then
    echo "[autodl] 未安装 tmux，改为当前终端运行" >&2
    run_server
    exit 0
  fi
  SESSION="${TMUX_SESSION:-breeze-tts}"
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[autodl] tmux 会话 $SESSION 已在运行，执行: tmux attach -t $SESSION"
    exit 0
  fi
  EXTRA=""
  if [[ "$MODE" == "once" ]]; then
    EXTRA="--once"
  fi
  tmux new-session -d -s "$SESSION" \
    bash -lc "cd '$ROOT' && exec bash deploy/autodl/start.sh $EXTRA"
  echo "[autodl] 已在 tmux 会话 $SESSION 中启动（看门狗=$MODE），查看: tmux attach -t $SESSION"
  exit 0
fi

run_server
