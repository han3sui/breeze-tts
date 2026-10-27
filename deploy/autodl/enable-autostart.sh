#!/usr/bin/env bash
# 注册开机自启。AutoDL 默认不跑 cron，所以同时写入：
#   1. crontab @reboot（cron 若被拉起来仍可用）
#   2. conda sitecustomize（Jupyter 开机必启，借它拉 Breeze）
#   3. /etc/profile.d（登录 shell 兜底）
# 关闭：bash deploy/autodl/enable-autostart.sh --off
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MARKER="breeze-tts-autodl"
BOOT_DELAY="${BOOT_DELAY:-20}"
ONSTART="$ROOT/deploy/autodl/autodl-onstart.sh"
PROFILE_SNIPPET="/etc/profile.d/breeze-tts-autostart.sh"
CRON_CMD="@reboot sleep ${BOOT_DELAY} && /bin/bash '$ONSTART' # ${MARKER}"

current() {
  crontab -l 2>/dev/null || true
}

remove_cron() {
  current | grep -v "# ${MARKER}" || true
}

site_packages() {
  local py="${PYTHON:-/root/miniconda3/bin/python}"
  if [[ ! -x "$py" ]]; then
    py="$(command -v python3 || command -v python || true)"
  fi
  [[ -n "$py" ]] || return 1
  "$py" -c "import site; print(site.getsitepackages()[0])"
}

install_sitecustomize() {
  local dest
  dest="$(site_packages)/sitecustomize.py"
  sed "s#/root/breeze-tts#$ROOT#g" "$ROOT/deploy/autodl/sitecustomize.py" > "$dest"
  echo "[autodl] sitecustomize -> $dest"
}

remove_sitecustomize() {
  local dest
  dest="$(site_packages)/sitecustomize.py" || return 0
  if [[ -f "$dest" ]] && grep -q "$MARKER" "$dest"; then
    rm -f "$dest"
    echo "[autodl] 已删除 $dest"
  fi
}

if [[ "${1:-}" == "--off" ]]; then
  if command -v crontab >/dev/null 2>&1; then
    remove_cron | crontab - || true
  fi
  rm -f "$PROFILE_SNIPPET"
  remove_sitecustomize || true
  echo "[autodl] 已取消开机自启"
  exit 0
fi

chmod +x "$ONSTART"

if ! command -v tmux >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  echo "[autodl] 安装 tmux，供开机后后台运行"
  apt-get update
  apt-get install -y --no-install-recommends tmux
fi

if command -v crontab >/dev/null 2>&1; then
  {
    remove_cron
    echo "$CRON_CMD"
  } | crontab -
fi

if command -v service >/dev/null 2>&1; then
  service cron start >/dev/null 2>&1 || true
fi

# Jupyter / TensorBoard 用的 conda Python 一启动就会跑 sitecustomize
install_sitecustomize

cat > "$PROFILE_SNIPPET" <<EOF
# ${MARKER} 登录兜底，不阻塞 shell
if [ -x $ONSTART ]; then
  ( /bin/bash $ONSTART >/tmp/breeze-tts-onstart.log 2>&1 & )
fi
EOF
chmod 644 "$PROFILE_SNIPPET"

echo "[autodl] 已注册开机自启（sitecustomize + crontab + profile.d）"
echo "[autodl] 控制台「启动脚本」也可填：bash $ONSTART"
crontab -l 2>/dev/null | grep "$MARKER" || true
