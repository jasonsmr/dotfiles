#!/data/data/com.termux/files/usr/bin/bash
# termux-gui.sh — Robust Termux:X11 + XFCE launcher with stable D-Bus & PulseAudio
# GPU: Mesa zink over Turnip (Adreno) or llvmpipe fallback. No root, no proot.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
PREFIX="/data/data/com.termux/files/usr"
HOME_DIR="$HOME"
LOG_DIR="$HOME/logs/Termux-GUI"
TMPDIR="$PREFIX/tmp"
XDG_RUNTIME_DIR="$HOME/tmp"
XAUTHORITY="$HOME/.Xauthority"

# proot-distro settings (can be overridden via env)
PROOT_DISTRO="${PROOT_DISTRO:-debian}"
PROOT_USER="${PROOT_USER:-droidmaster}"

mkdir -p "$LOG_DIR" "$TMPDIR" "$XDG_RUNTIME_DIR" "$HOME/.cache" "$HOME/.config/pulse"

# --- Keep GUI runtime clean (avoid ABI/toolchain clashes) ---
export PATH="$HOME/bin:$PREFIX/bin:/system/bin"
export LD_LIBRARY_PATH="$PREFIX/lib"

# --- Mesa/DRI/GBM hints ---
export LIBGL_DRIVERS_PATH="$PREFIX/lib/dri"
export __GLX_VENDOR_LIBRARY_NAME="mesa"
export GBM_BACKENDS_PATH="$PREFIX/lib/gbm"

# --- GPU mode handling ---
GPU_MODE="${GPU_MODE:-auto}"
FREEDRENO_JSON="$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json"  # Turnip
LVP_JSON="$PREFIX/share/vulkan/icd.d/lvp_icd.aarch64.json"              # Lavapipe

log() { printf '[%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S %Z")" "$*" | tee -a "$LOG_DIR/status.log"; }

set_gpu_env() {
  case "$GPU_MODE" in
    zink)
      export LIBGL_ALWAYS_SOFTWARE=0
      export MESA_LOADER_DRIVER_OVERRIDE=zink
      if [[ -f "$FREEDRENO_JSON" ]]; then
        export VK_ICD_FILENAMES="$FREEDRENO_JSON"
      else
        unset VK_ICD_FILENAMES || true
        log "[WARN] Turnip ICD missing at $FREEDRENO_JSON; zink may fallback."
      fi
      log "[GPU] Mode=zink (OpenGL over Vulkan via zink; ICD=freedreno if present)"
      ;;
    llvmpipe)
      export LIBGL_ALWAYS_SOFTWARE=1
      unset MESA_LOADER_DRIVER_OVERRIDE VK_ICD_FILENAMES || true
      log "[GPU] Mode=llvmpipe (software GL)"
      ;;
    auto|*)
      unset LIBGL_ALWAYS_SOFTWARE MESA_LOADER_DRIVER_OVERRIDE || true
      if [[ -f "$FREEDRENO_JSON" ]]; then
        export VK_ICD_FILENAMES="$FREEDRENO_JSON"
        log "[GPU] Mode=auto (ICD=freedreno; Mesa chooses GL driver, zink possible)"
      else
        unset VK_ICD_FILENAMES || true
        log "[GPU] Mode=auto (no ICD hint; Mesa chooses)"
      fi
      ;;
  esac
}

# --- Doctor (sanity without starting services) ---
doctor() {
  log "=== Doctor: checking prerequisites ==="
  for tool in termux-x11 startxfce4 dbus-daemon pulseaudio am xauth xdpyinfo xhost vulkaninfo glxinfo proot-distro; do
    if command -v "$tool" >/dev/null 2>&1; then log "[OK]   tool: $tool"; else log "[WARN] tool missing: $tool"; fi
  done
  for dir in "$TMPDIR" "$LOG_DIR"; do mkdir -p "$dir"; log "[OK]   dir: $dir"; done

  if [[ -d "$PREFIX/share/vulkan/icd.d" ]]; then
    log "[GPU] ICD.d contents:"
    ls -1 "$PREFIX/share/vulkan/icd.d" | sed 's/^/       - /' | tee -a "$LOG_DIR/status.log" >/dev/null
    [[ -f "$FREEDRENO_JSON" ]] && log "[GPU] Turnip ICD present: $FREEDRENO_JSON"
    [[ -f "$LVP_JSON" ]] && log "[GPU] Lavapipe ICD present: $LVP_JSON"
  else
    log "[WARN] No ICD directory at $PREFIX/share/vulkan/icd.d"
  fi
}

# --- D-Bus (session daemon w/ explicit UNIX socket) ---
DBUS_SOCK_DIR="$TMPDIR/dbus"
DBUS_ADDR_FILE="$HOME/.dbus-session"
start_dbus() {
  log "[STEP] Starting D-Bus (session) ..."
  mkdir -p "$DBUS_SOCK_DIR"; chmod 700 "$DBUS_SOCK_DIR"
  rm -f "$DBUS_SOCK_DIR/session.sock" "$DBUS_ADDR_FILE" || true
  local DBUS_ADDR="unix:path=${DBUS_SOCK_DIR}/session.sock"
  dbus-daemon --session --address="$DBUS_ADDR" --print-address --fork >>"$LOG_DIR/dbus.log" 2>&1
  export DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR"
  printf "export DBUS_SESSION_BUS_ADDRESS='%s'\n" "$DBUS_SESSION_BUS_ADDRESS" >"$DBUS_ADDR_FILE"
  log "[OK]   D-Bus: $DBUS_SESSION_BUS_ADDRESS"
}

dbus_watchdog() {
  while true; do
    if ! pgrep -f "dbus-daemon --session" >/dev/null 2>&1; then
      log "[WD] dbus-daemon crashed. Restarting..."
      start_dbus
    fi
    sleep 5
  done >>"$LOG_DIR/dbus_watchdog.log" 2>&1 &
}

# --- PulseAudio (AAudio/OpenSL ES → fallback null) ---
PA_SOCK="$TMPDIR/pulse-native.sock"

_start_pulse_null() {
  pulseaudio -n --daemonize=yes \
    --exit-idle-time=-1 --realtime=false --high-priority=false \
    --log-target=file:"$LOG_DIR/pulseaudio.log" \
    --load="module-native-protocol-unix auth-anonymous=1 socket=$PA_SOCK" \
    --load="module-null-sink sink_name=termux_out sink_properties=device.description=TermuxOutput" \
    --load="module-null-source source_name=termux_in  source_properties=device.description=TermuxInput" \
    >>"$LOG_DIR/pulseaudio.log" 2>&1 || true
  echo "termux_out" > "$TMPDIR/.default-sink"
}

_start_pulse_sles() {
  pulseaudio -n --daemonize=yes \
    --exit-idle-time=-1 --realtime=false --high-priority=false \
    --log-target=file:"$LOG_DIR/pulseaudio.log" \
    --load="module-native-protocol-unix auth-anonymous=1 socket=$PA_SOCK" \
    --load="module-sles-sink sink_name=android_sles" \
    >>"$LOG_DIR/pulseaudio.log" 2>&1 || true
  echo "android_sles" > "$TMPDIR/.default-sink"
}

_start_pulse_aaudio() {
  pulseaudio -n --daemonize=yes \
    --exit-idle-time=-1 --realtime=false --high-priority=false \
    --log-target=file:"$LOG_DIR/pulseaudio.log" \
    --load="module-native-protocol-unix auth-anonymous=1 socket=$PA_SOCK" \
    --load="module-aaudio-sink sink_name=android_aaudio rate=48000 latency=40 pm=2" \
    >>"$LOG_DIR/pulseaudio.log" 2>&1 || true
  echo "android_aaudio" > "$TMPDIR/.default-sink"
}

start_pulseaudio() {
  log "[STEP] Starting PulseAudio ..."
  pulseaudio -k >/dev/null 2>&1 || true
  rm -f "$PA_SOCK" || true
  mkdir -p "$HOME/.config/pulse"

  # Clients use our UNIX socket; don't autospawn their own server
  cat > "$HOME/.config/pulse/client.conf" <<EOF
autospawn = no
default-server = unix:$PA_SOCK
EOF

  # Detect by "Name: ..." lines (Termux format). Allow explicit overrides.
  HAS_AAUDIO="$(pulseaudio --dump-modules 2>/dev/null | grep -c 'Name: module-aaudio-sink' || true)"
  HAS_SLES="$(pulseaudio --dump-modules 2>/dev/null | grep -c 'Name: module-sles-sink' || true)"

  if [ "${TG_PULSE_FORCE_AAUDIO:-0}" = "1" ] && [ "$HAS_AAUDIO" -gt 0 ]; then
    _start_pulse_aaudio
    log "[OK]   PulseAudio: forced module-aaudio-sink"
  elif [ "${TG_PULSE_FORCE_SLES:-0}" = "1" ] && [ "$HAS_SLES" -gt 0 ]; then
    _start_pulse_sles
    log "[OK]   PulseAudio: forced module-sles-sink"
  elif [ "$HAS_AAUDIO" -gt 0 ]; then
    _start_pulse_aaudio
    log "[OK]   PulseAudio: using module-aaudio-sink"
  elif [ "$HAS_SLES" -gt 0 ]; then
    _start_pulse_sles
    log "[OK]   PulseAudio: using module-sles-sink"
  else
    _start_pulse_null
    log "[WARN] PulseAudio: neither AAudio nor OpenSL ES available; using null sink"
  fi

  export PULSE_SERVER="unix:$PA_SOCK"
  printf "export PULSE_SERVER='%s'\n" "$PULSE_SERVER" > "$HOME/.pulse-session"

  # Set default sink if pactl can reach the server
  if command -v pactl >/dev/null 2>&1; then
    sleep 0.2
    DEFAULT_SINK="$(cat "$TMPDIR/.default-sink" 2>/dev/null || true)"
    [ -n "$DEFAULT_SINK" ] && pactl set-default-sink "$DEFAULT_SINK" >/dev/null 2>&1 || true
  fi

  log "[OK]   PulseAudio: server=$PULSE_SERVER"
}

pulseaudio_watchdog() {
  while true; do
    if ! pgrep -f "[p]ulseaudio" >/dev/null 2>&1; then
      log "[WD] PulseAudio crashed. Restarting..."
      start_pulseaudio
    fi
    sleep 5
  done >>"$LOG_DIR/pulseaudio_watchdog.log" 2>&1 &
}

# --- X11 / XFCE (native) ---
start_x11() {
  log "[STEP] Starting Termux:X11 ..."
  rm -f "$XDG_RUNTIME_DIR/.X11-unix/X0" "$TMPDIR/.X11-unix/X0" 2>/dev/null || true
  mkdir -p "$XDG_RUNTIME_DIR/.X11-unix" "$TMPDIR/.X11-unix"
  termux-x11 :0 >>"$LOG_DIR/termux-x11.log" 2>&1 &
  sleep 2
  am start --user 0 -n com.termux.x11/.MainActivity >>"$LOG_DIR/termux-x11.log" 2>&1 || true
  sleep 2
  if ! DISPLAY=:0 xdpyinfo >/dev/null 2>&1; then
    log "[WARN] Termux:X11 not responding yet, retry with -listen tcp"
    pkill -9 -f termux.x11 || true
    rm -f "$XDG_RUNTIME_DIR/.X11-unix/X0" "$TMPDIR/.X11-unix/X0" || true
    termux-x11 :0 -listen tcp >>"$LOG_DIR/termux-x11.log" 2>&1 &
    sleep 2
  fi
  log "[OK]   Termux:X11 started."
}

start_xfce_native() {
  log "[STEP] Starting XFCE4 (native) ..."
  export DISPLAY=":0"
  export XDG_RUNTIME_DIR
  export XAUTHORITY
  if command -v xauth >/dev/null 2>&1; then
    xauth add :0 . "$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -ve '1/1 "%.2x"')" \
      >>"$LOG_DIR/xfce4_start.log" 2>&1 || true
  fi
  if ! xdpyinfo >/dev/null 2>&1; then export DISPLAY="localhost:0"; fi
  ( env | sort ) >"$LOG_DIR/env.log"
  startxfce4 >>"$LOG_DIR/xfce4_start.log" 2>&1 &
  log "[OK]   XFCE4 (native) start invoked."
}

# --- XFCE inside proot-distro (Debian) ---
start_xfce_proot() {
  log "[STEP] Starting XFCE4 inside proot-distro ($PROOT_DISTRO as $PROOT_USER) ..."
  export DISPLAY=":0"
  export XDG_RUNTIME_DIR
  export XAUTHORITY
  # Make sure host env is logged for debugging
  ( env | sort ) >"$LOG_DIR/env_proot_outer.log"

  # Command executed inside the proot Debian environment
  local inner_cmd
  inner_cmd=$(cat <<EOF
export DISPLAY=":0"
export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
export DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
export PULSE_SERVER="$PULSE_SERVER"
env | sort > "\$HOME/env_proot_inner.log"
su - "$PROOT_USER" -c "startxfce4"
EOF
)

  proot-distro login "$PROOT_DISTRO" --shared-tmp -- /bin/bash -lc "$inner_cmd" >>"$LOG_DIR/xfce4_proot.log" 2>&1 &
  log "[OK]   XFCE4 (proot/$PROOT_DISTRO) start invoked."
}

# --- Helpers to test/trace Vulkan & GL ---
clean_env_prefix() {
  env -i HOME="$HOME" TERM="$TERM" PATH="$PREFIX/bin:/system/bin" LD_LIBRARY_PATH="$PREFIX/lib" "$@"
}

test_vulkan() {
  local which="${1:-freedreno}"
  case "$which" in
    freedreno|turnip) clean_env_prefix VK_ICD_FILENAMES="$FREEDRENO_JSON" vulkaninfo | sed -n '1,120p' || true ;;
    lvp|lavapipe)     clean_env_prefix VK_ICD_FILENAMES="$LVP_JSON"      vulkaninfo | sed -n '1,120p' || true ;;
    *) echo "Usage: $SCRIPT_NAME test-vulkan [freedreno|lvp]"; return 1 ;;
  esac
}

trace_vulkan() {
  local which="${1:-freedreno}" icd
  case "$which" in
    freedreno|turnip) icd="$FREEDRENO_JSON" ;;
    lvp|lavapipe)     icd="$LVP_JSON" ;;
    *) echo "Usage: $SCRIPT_NAME trace-vulkan [freedreno|lvp]"; return 1 ;;
  esac
  log "[TRACE] Stracing vulkaninfo with ICD=$icd"
  clean_env_prefix VK_ICD_FILENAMES="$icd" \
    strace -f -o "$LOG_DIR/vulkaninfo.strace" vulkaninfo >/dev/null 2>&1 || true
  tail -n 80 "$LOG_DIR/vulkaninfo.strace" | sed 's/^/[TRACE] /' | tee -a "$LOG_DIR/status.log" >/dev/null
  log "[TRACE] Full trace at: $LOG_DIR/vulkaninfo.strace"
}

test_gl() {
  local which="${1:-zink}"
  case "$which" in
    zink)
      MESA_LOADER_DRIVER_OVERRIDE=zink \
      VK_ICD_FILENAMES="$FREEDRENO_JSON" \
      DISPLAY=":0" glxinfo -B | grep -E 'OpenGL renderer|OpenGL vendor|OpenGL version' || true
      ;;
    llvmpipe)
      LIBGL_ALWAYS_SOFTWARE=1 DISPLAY=":0" glxinfo -B | grep 'OpenGL renderer' || true
      ;;
    *) echo "Usage: $SCRIPT_NAME test-gl [zink|llvmpipe]"; return 1 ;;
  esac
}

# --- Core stack bring-up shared by native + proot ---
core_stack_up() {
  set_gpu_env
  doctor

  log "[CLEAN] Purging runtime dirs"
  rm -rf "$DBUS_SOCK_DIR" "$TMPDIR/.X11-unix" || true
  mkdir -p "$DBUS_SOCK_DIR" "$TMPDIR/.X11-unix"

  start_dbus
  dbus_watchdog
  start_pulseaudio
  pulseaudio_watchdog
  start_x11
}

# --- Main start/stop/status ---
start() {
  local DEBUG=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug) DEBUG=1; shift;;
      --gpu-mode|--gpu-made) GPU_MODE="${2:-auto}"; shift 2;;
      *) break;;
    esac
  done

  core_stack_up
  start_xfce_native

  log "XFCE/X11 launch sequence complete (native)."
  if [[ "$DEBUG" == "1" ]]; then
    log "[DEBUG] Live log tail (Ctrl-C to exit)"
    tail -f "$LOG_DIR"/*.log
  fi
}

start_debian() {
  local DEBUG=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug) DEBUG=1; shift;;
      --gpu-mode|--gpu-made) GPU_MODE="${2:-auto}"; shift 2;;
      *) break;;
    esac
  done

  core_stack_up
  start_xfce_proot

  log "XFCE/X11 launch sequence complete (proot/$PROOT_DISTRO)."
  if [[ "$DEBUG" == "1" ]]; then
    log "[DEBUG] Live log tail (Ctrl-C to exit)"
    tail -f "$LOG_DIR"/*.log
  fi
}

stop() {
  log "[STEP] Stopping XFCE/X11 session ..."
  pkill -9 -f startxfce4 || true
  pkill -9 -f xfce4-session || true
  pkill -9 -f termux.x11 || true
  pkill -9 -f pulseaudio || true
  pkill -9 -f "dbus-daemon --session" || true
  pkill -9 -f dbus_watchdog || true
  pkill -9 -f pulseaudio_watchdog || true
  rm -f "$DBUS_ADDR_FILE" "$PA_SOCK" || true
  log "[OK]   Stopped session. Cleaned D-Bus address and Pulse socket."
}

status() {
  log "=== Status / Health Check ==="

  # dbus-daemon can be launched with different argv; detect by socket + env too
  DBUS_OK=1
  if ! pgrep -fa "dbus-daemon" | grep -q -- "--session"; then
    if [ -S "$TMPDIR/dbus/session.sock" ] || [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      DBUS_OK=0
    fi
  fi
  if pgrep -fa "dbus-daemon" | grep -q -- "--session"; then
    log "[OK]   dbus-daemon running"
  elif [ $DBUS_OK -eq 0 ]; then
    log "[OK]   dbus-daemon session socket present (process name heuristic failed)"
  else
    log "[ERR]  dbus-daemon not running"
  fi

  pgrep -a pulseaudio   >/dev/null 2>&1 && log "[OK]   pulseaudio running"   || log "[ERR]  pulseaudio not running"
  pgrep -fa termux.x11  >/dev/null 2>&1 && log "[OK]   termux-x11 running"   || log "[ERR]  termux-x11 not running"
  pgrep -a xfce4-session>/dev/null 2>&1 && log "[OK]   xfce4-session running"|| log "[ERR]  xfce4-session not running"

  # Show current sink
  if command -v pactl >/dev/null 2>&1; then
    SINK_LINE="$(pactl list short sinks 2>/dev/null | head -n1 || true)"
    [ -n "$SINK_LINE" ] && log "[AUDIO] sink: $SINK_LINE"
  fi

  log ""
  log "[ENV]  DISPLAY=${DISPLAY:-unset}"
  log "[ENV]  DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unset}"
  if [ -z "${PULSE_SERVER:-}" ] && [ -f "$HOME/.pulse-session" ]; then
    # shellcheck disable=SC1090
    source "$HOME/.pulse-session"
  fi
  log "[ENV]  PULSE_SERVER=${PULSE_SERVER:-unset}"
  log "[ENV]  GPU_MODE=${GPU_MODE:-auto}"
  log "[ENV]  VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-unset}"
  log "[ENV]  MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-unset}"
  log "[ENV]  LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-unset}"
  log "[ENV]  PROOT_DISTRO=${PROOT_DISTRO:-debian}"
  log "[ENV]  PROOT_USER=${PROOT_USER:-droidmaster}"
}

case "${1:-}" in
  start) shift; start "$@" ;;
  start-debian) shift; start_debian "$@" ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  doctor) doctor ;;
  test-vulkan) shift; test_vulkan "${1:-freedreno}" ;;
  trace-vulkan) shift; trace_vulkan "${1:-freedreno}" ;;
  test-gl) shift; test_gl "${1:-zink}" ;;
  *)
    echo "Usage: $SCRIPT_NAME {start|start-debian|stop|restart|status|doctor|test-vulkan|trace-vulkan|test-gl} [opts]"
    echo "  start          [--debug] [--gpu-mode auto|zink|llvmpipe]   # native XFCE"
    echo "  start-debian   [--debug] [--gpu-mode auto|zink|llvmpipe]   # XFCE in proot-distro \$PROOT_DISTRO as \$PROOT_USER"
    echo "  test-vulkan    [freedreno|lvp]    # run vulkaninfo in a clean env"
    echo "  trace-vulkan   [freedreno|lvp]    # strace vulkaninfo to logs"
    echo "  test-gl        [zink|llvmpipe]    # show GL renderer via glxinfo"
    exit 1 ;;
esac
