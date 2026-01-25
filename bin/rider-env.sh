#!/data/data/com.termux/files/usr/bin/bash
# rider-env.sh — shared environment bootstrap for Rider on Termux

set -euo pipefail

mode="${1:-${ENV_MODE:-mingw-hybrid}}"

export TMP="${TMP:-$HOME/tmp}"
export TMPDIR="${TMPDIR:-$TMP}"
mkdir -p "$TMP" "$HOME/.cache" "$HOME/.config" || true

if [ -f "$HOME/.env_modes.sh" ]; then
  # shellcheck disable=SC1090
  source "$HOME/.env_modes.sh" "$mode"
else
  echo "[rider-env][WARN] Missing $HOME/.env_modes.sh (mode switch skipped)" >&2
fi

JB_NATIVE_LIBS="${JB_NATIVE_LIBS:-$HOME/opt/jetbrains/native-libs}"
mkdir -p "$JB_NATIVE_LIBS" || true

export JNA_LIBRARY_PATH="${JNA_LIBRARY_PATH:-$JB_NATIVE_LIBS}"
export LD_LIBRARY_PATH="$JB_NATIVE_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:/system/bin"
export ENV_MODE="$mode"

# Rider caveat: the official Linux ARM64 Rider backend is usually **glibc**.
# If you do not have a working glibc lane (loader + libs) you will see ENOENT on Rider.Backend.
