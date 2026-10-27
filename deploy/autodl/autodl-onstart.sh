#!/usr/bin/env bash
# AutoDL 开机入口：拉起 cron（若有）并保证 breeze-tts tmux 在跑。可重复执行。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH}"

if command -v service >/dev/null 2>&1; then
  service cron start >/dev/null 2>&1 || true
fi

# 等 NVIDIA 设备出现（镜像刚起来时 nvidia-smi 可能还没有）
i=0
while [[ "$i" -lt 30 ]]; do
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    break
  fi
  i=$((i + 1))
  sleep 2
done

exec bash "$ROOT/deploy/autodl/start.sh" --tmux
