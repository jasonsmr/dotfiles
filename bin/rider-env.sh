#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# ---- user-tunable paths ----
RIDER_HOME_DEFAULT="$HOME/opt/jetbrains/rider"
TERMUX_JDK_DEFAULT="$PREFIX/lib/jvm/java-21-openjdk"

# Resolve Rider install dir (symlink ok)
RIDER_HOME="${RIDER_HOME:-$RIDER_HOME_DEFAULT}"
if [ -L "$RIDER_HOME" ]; then
  RIDER_HOME="$(readlink -f "$RIDER_HOME")"
fi

if [ ! -d "$RIDER_HOME/bin" ]; then
  echo "[rider-env] ERROR: RIDER_HOME invalid: $RIDER_HOME"
  echo "[rider-env] Expected: $HOME/opt/jetbrains/rider/bin"
  exit 1
fi

# Termux OpenJDK (bionic) — required on Android
TERMUX_JDK="${TERMUX_JDK:-$TERMUX_JDK_DEFAULT}"
if [ ! -x "$TERMUX_JDK/bin/java" ]; then
  echo "[rider-env] ERROR: Termux JDK not found/executable: $TERMUX_JDK/bin/java"
  exit 1
fi

# ---- env-modes ----
# You said modes live here and can be switched by name (mingw-hybrid, etc.)
if [ -f "$HOME/.env_modes.sh" ]; then
  # shellcheck disable=SC1090
  source "$HOME/.env_modes.sh"
fi

# Mode selection:
# 1) first CLI arg to rider-start
# 2) ENV_MODE if set
# 3) leave as-is
REQUESTED_MODE="${1:-${ENV_MODE:-}}"
export ENV_MODE="${REQUESTED_MODE:-${ENV_MODE:-}}"

# If your env-modes define a function like: env_mode_set <name>
# or mode_<name>, you can hook it here without breaking anything.
if [ -n "${REQUESTED_MODE:-}" ]; then
  if command -v env_mode_set >/dev/null 2>&1; then
    env_mode_set "$REQUESTED_MODE" || true
  elif command -v "mode_${REQUESTED_MODE//-/_}" >/dev/null 2>&1; then
    "mode_${REQUESTED_MODE//-/_}" || true
  fi
fi

# ---- toolchain hygiene (NO host leakage into builds) ----
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH PKG_CONFIG_PATH
# Keep your wrappers first
export PATH="$HOME/bin:$PREFIX/bin:/system/bin"

# ---- X11 / runtime dirs ----
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/tmp}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
mkdir -p "$XDG_RUNTIME_DIR"

# ---- Mesa / Vulkan: keep accel (don’t force llvmpipe) ----
# If you WANT to pin Turnip+Zink, set these before launching:
#   export VK_ICD_FILENAMES="$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json"
#   export MESA_LOADER_DRIVER_OVERRIDE=zink
#   export GALLIUM_DRIVER=zink
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-mesa}"

# ---- JDK wiring for Rider ----
export RIDER_JDK="$TERMUX_JDK"
export JAVA_HOME="$TERMUX_JDK"
export PATH="$JAVA_HOME/bin:$PATH"

# ---- Rider stability on Android/bionic ----
# Create a per-launch vmoptions file.
VM_TMP_DIR="${VM_TMP_DIR:-$HOME/tmp/jetbrains-vmoptions}"
mkdir -p "$VM_TMP_DIR"
RIDER_VMOPTS_FILE="$VM_TMP_DIR/rider64.android.vmoptions"

cat > "$RIDER_VMOPTS_FILE" <<'EOF'
# Android/bionic survivability options
-Dide.browser.jcef.enabled=false
-Dide.browser.jcef.sandbox.enable=false
-Djb.privacy.policy.text=<!-- -->
-Djb.consents.confirmation.enabled=false

# Disable native file watcher (bundled fsnotifier is glibc)
-Didea.filewatcher.disabled=true

# Reduce random native probing pain
-Dsun.java2d.xrender=false
EOF

export RIDER_VM_OPTIONS="$RIDER_VMOPTS_FILE"

# Let rider-termux do the final exec
exec "$HOME/bin/rider-termux"

