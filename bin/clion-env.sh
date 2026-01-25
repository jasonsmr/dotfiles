#!/data/data/com.termux/files/usr/bin/bash
# clion-env.sh — shared environment bootstrap for CLion on Termux

set -euo pipefail

mode="${1:-${ENV_MODE:-mingw-hybrid}}"

export TMP="${TMP:-$HOME/tmp}"
export TMPDIR="${TMPDIR:-$TMP}"
mkdir -p "$TMP" "$HOME/.cache" "$HOME/.config" || true

# Authoritative env switching
if [ -f "$HOME/.env_modes.sh" ]; then
  # shellcheck disable=SC1090
  source "$HOME/.env_modes.sh" "$mode"
else
  echo "[clion-env][WARN] Missing $HOME/.env_modes.sh (mode switch skipped)" >&2
fi

# JetBrains-native libs (bionic builds you add) can live here
JB_NATIVE_LIBS="${JB_NATIVE_LIBS:-$HOME/opt/jetbrains/native-libs}"
mkdir -p "$JB_NATIVE_LIBS" || true

# Help JNA locate native deps like libe2p.so (and any other small helpers)
export JNA_LIBRARY_PATH="${JNA_LIBRARY_PATH:-$JB_NATIVE_LIBS}"
export LD_LIBRARY_PATH="$JB_NATIVE_LIBS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Keep IDE runtime clean: prefer Termux user bins first
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:/system/bin"

export ENV_MODE="$mode"
