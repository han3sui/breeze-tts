#!/usr/bin/env bash
# 写入 crontab @reboot，实例开机后自动拉起 start.sh --tmux（内含看门狗）
# 关闭：bash deploy/autodl/enable-autostart.sh --off
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MARKER="breeze-tts-autodl"
# 等 GPU / 网络就绪后再启
BOOT_DELAY="${BOOT_DELAY:-20}"
CRON_CMD="@reboot sleep ${BOOT_DELAY} && /bin/bash -lc 'cd \"$ROOT\" && bash deploy/autodl/start.sh --tmux' # ${MARKER}"

if ! command -v crontab >/dev/null 2>&1; then
  echo "[autodl] 系统没有 crontab，无法注册开机自启" >&2
  exit 1
fi

current() {
  crontab -l 2>/dev/null || true
}

remove_marker() {
  current | grep -v "# ${MARKER}" || true
}

if [[ "${1:-}" == "--off" ]]; then
  remove_marker | crontab -
  echo "[autodl] 已取消开机自启"
  exit 0
fi

if ! command -v tmux >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  echo "[autodl] 安装 tmux，供开机后后台运行"
  apt-get update
  apt-get install -y --no-install-recommends tmux
fi

{
  remove_marker
  echo "$CRON_CMD"
} | crontab -

# 部分 AutoDL 镜像 cron 未启动
if command -v service >/dev/null 2>&1; then
  service cron start >/dev/null 2>&1 || true
fi

echo "[autodl] 已注册开机自启（${BOOT_DELAY}s 后 start.sh --tmux）"
crontab -l | grep "$MARKER" || true
