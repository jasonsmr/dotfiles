#!/data/data/com.termux/files/usr/bin/bash
# rider-debian-env.sh — prepare environment for running Rider inside proot Debian
set -euo pipefail

PREFIX="/data/data/com.termux/files/usr"
USER_HOME="$HOME"
TMPROOT="${PREFIX}/tmp"

mkdir -p "${TMPROOT}" "${TMPROOT}/.X11-unix" "${USER_HOME}/tmp" || true

export DISPLAY="${DISPLAY:-:0}"

# Allow local unix-socket clients (proot) to connect to Termux:X11
if command -v xhost >/dev/null 2>&1; then
  xhost +local: >/dev/null 2>&1 || true
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$USER_HOME/tmp}"
mkdir -p "$XDG_RUNTIME_DIR" || true
