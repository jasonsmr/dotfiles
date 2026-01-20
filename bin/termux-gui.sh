#!/data/data/com.termux/files/usr/bin/bash
# termux-gui.sh â€” Stable Termux:X11 + XFCE launcher (native + proot Debian)
# Version: v10 (adds PA_PIDFILE, robust pid capture) (fixes PulseAudio module-native-protocol-unix args for PA17)
#
# Key fixes vs v7:
# - PulseAudio module-native-protocol-unix does NOT accept "shm=0" in Termux PA 17.x builds.
#   (That was causing: "Failed to parse module arguments" and the socket never got created.)
# - We disable SHM the correct way via PulseAudio config: daemon.conf + client.conf "enable-shm = no".
#
# Goals:
# - Deterministic startup (X11 â†’ D-Bus â†’ PulseAudio â†’ XFCE)
# - Proot mode runs xfce4-session (NOT startxfce4) to avoid trying to start Xorg
# - Shared /tmp paths are used for proot (because proot-distro --shared-tmp maps Termux $PREFIX/tmp <-> /tmp)

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
PREFIX="/data/data/com.termux/files/usr"
TMPDIR="$PREFIX/tmp"

# ---- user-ish identity (Termux often does NOT export $USER) ----
TG_HOST_USER="${USER:-$(id -un 2>/dev/null || true)}"
[ -n "$TG_HOST_USER" ] || TG_HOST_USER="termux"

# ---- paths ----
LOG_DIR="$HOME/logs/Termux-GUI"
XDG_RUNTIME_DIR_DEFAULT="$TMPDIR/xdg-runtime-${TG_HOST_USER}"
XAUTHORITY_DEFAULT="$HOME/.Xauthority"

# ---- display ----
DISPLAY_NUM="${DISPLAY_NUM:-0}"
DISPLAY=":${DISPLAY_NUM}"

# ---- D-Bus (session bus hosted by Termux side) ----
DBUS_SOCK_DIR="$TMPDIR/dbus"
DBUS_SOCK="$DBUS_SOCK_DIR/session.sock"
DBUS_PIDFILE="$DBUS_SOCK_DIR/session.pid"
DBUS_ADDR_FILE="$LOG_DIR/dbus.addr.sh"     # sourced by other shells
DBUS_LOCK="$DBUS_SOCK_DIR/session.lock"

# ---- PulseAudio ----
PA_SOCK="$TMPDIR/pulse-native.sock"
PA_PIDFILE="$TMPDIR/pulseaudio.pid"

# ---- proot config ----
PROOT_DISTRO="${PROOT_DISTRO:-debian}"
PROOT_USER="${PROOT_USER:-droidmaster}"

# ---- behavior flags ----
QUIET=0
DEBUG=0

mkdir -p "$LOG_DIR" "$TMPDIR" "$DBUS_SOCK_DIR" "$XDG_RUNTIME_DIR_DEFAULT" "$HOME/.config/pulse"
# Choose a runtime dir that works for BOTH host + proot (shared tmp)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$XDG_RUNTIME_DIR_DEFAULT}"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/gvfsd"
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"
export PULSE_STATE_PATH="$HOME/.config/pulse"
chmod 700 "$XDG_RUNTIME_DIR" || true

ts() { date '+[%Y-%m-%d %H:%M:%S %Z]'; }
log() {
  local line; line="$(ts) $*"
  printf '%s\n' "$line" >>"$LOG_DIR/status.log"
  if [ "$QUIET" -eq 0 ]; then printf '%s\n' "$line"; fi
}
die() { log "[ERR]  $*"; exit 1; }

# -------------------- Doctor --------------------
doctor() {
  log "=== Doctor: checking prerequisites ==="
  local missing=0
  for t in termux-x11 am xdpyinfo xhost dbus-daemon pulseaudio pactl; do
    if command -v "$t" >/dev/null 2>&1; then
      log "[OK]   tool: $t"
    else
      log "[ERR]  missing tool: $t"
      missing=1
    fi
  done
  if command -v proot-distro >/dev/null 2>&1; then
    log "[OK]   tool: proot-distro"
  else
    log "[WARN] proot-distro not found (native-only mode)"
  fi
  log "[OK]   dir: $TMPDIR"
  log "[OK]   dir: $LOG_DIR"
  [ "$missing" -eq 0 ] || return 1
}

# -------------------- X11 --------------------
clean_x_state() {
  log "[CLEAN] Cleaning X state for DISPLAY=$DISPLAY"
  pkill -9 -f "termux-x11" >/dev/null 2>&1 || true
  pkill -9 -f "com.termux.x11" >/dev/null 2>&1 || true
  rm -rf "$TMPDIR/.X11-unix" || true
  mkdir -p "$TMPDIR/.X11-unix"
  mkdir -p "$TMPDIR/.ICE-unix"
  chmod 1777 "$TMPDIR/.ICE-unix" || true
  rm -f "$TMPDIR/.X${DISPLAY_NUM}-lock" || true
}

start_x11_strict() {
  local xdg="${XDG_RUNTIME_DIR:-$XDG_RUNTIME_DIR_DEFAULT}"
  local xauth="${XAUTHORITY:-$XAUTHORITY_DEFAULT}"

  export DISPLAY="$DISPLAY"
  export XDG_RUNTIME_DIR="$xdg"
  export XAUTHORITY="$xauth"

  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    log "[OK]   X already reachable on $DISPLAY"
    return 0
  fi

  clean_x_state

  log "[STEP] Starting Termux:X11 appâ€¦"
  am start -n com.termux.x11/.MainActivity >>"$LOG_DIR/termux-x11.log" 2>&1 || true

  log "[STEP] Starting Termux:X11 server on $DISPLAYâ€¦"
  ( termux-x11 "$DISPLAY" >>"$LOG_DIR/termux-x11.log" 2>&1 ) & disown || true

  local i
  for i in $(seq 1 60); do
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
      log "[OK]   X is up on $DISPLAY"
      xhost +local: >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.15
  done

  log "[ERR]  X never became reachable on $DISPLAY"
  log "[HINT] Check: $LOG_DIR/termux-x11.log"
  return 1
}

# -------------------- D-Bus --------------------
dbus_healthcheck() {
  dbus-send --session --dest=org.freedesktop.DBus \
    --type=method_call /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
    >/dev/null 2>&1
}

start_dbus() {
  mkdir -p "$DBUS_SOCK_DIR"
  chmod 700 "$DBUS_SOCK_DIR" || true

  exec 9>"$DBUS_LOCK"
  if command -v flock >/dev/null 2>&1; then
    flock -n 9 || { log "[OK]   D-Bus lock held elsewhere; assuming running"; return 0; }
  fi

  if [ -s "$DBUS_PIDFILE" ]; then
    local pid; pid="$(cat "$DBUS_PIDFILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_SOCK"
      if dbus_healthcheck; then
        printf "export DBUS_SESSION_BUS_ADDRESS=%q\n" "$DBUS_SESSION_BUS_ADDRESS" >"$DBUS_ADDR_FILE"
        log "[OK]   D-Bus already healthy: $DBUS_SESSION_BUS_ADDRESS (pid=$pid)"
        return 0
      fi
    fi
  fi

  pkill -9 -f "dbus-daemon --session" >/dev/null 2>&1 || true
  rm -f "$DBUS_SOCK" "$DBUS_PIDFILE" "$DBUS_ADDR_FILE" || true

  log "[STEP] Starting D-Bus (session)â€¦"
  dbus-daemon --session \
    --fork \
    --address="unix:path=$DBUS_SOCK" \
    --print-address=1 \
    --print-pid=1 \
    >>"$LOG_DIR/dbus.log" 2>&1 || true

  local pid
  pid="$(pgrep -f "dbus-daemon --session.*unix:path=$DBUS_SOCK" | head -n 1 || true)"
  [ -n "${pid:-}" ] && printf '%s\n' "$pid" >"$DBUS_PIDFILE" || true

  export DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_SOCK"
  printf "export DBUS_SESSION_BUS_ADDRESS=%q\n" "$DBUS_SESSION_BUS_ADDRESS" >"$DBUS_ADDR_FILE"

  if dbus_healthcheck; then
    log "[OK]   D-Bus healthy: $DBUS_SESSION_BUS_ADDRESS (pid=${pid:-?})"
  else
    log "[ERR]  D-Bus did not respond; check $LOG_DIR/dbus.log"
    return 1
  fi
}


# -------------------- PulseAudio --------------------
# NOTE: Termux builds vary. "pulseaudio --dump-modules" output is not stable, so
# we detect optional backends by checking module *.so presence on disk.
# We always try to bring up the unix socket first; then we ensure a real sink
# exists (AAudio/OpenSL) and fall back to null if not available.

_pulse_moddir() {
  # Termux default. If user moved PREFIX, respect $PREFIX.
  local d="${PREFIX}/lib/pulseaudio/modules"
  [ -d "$d" ] && { printf '%s
' "$d"; return 0; }
  # Fallback: ask pulseaudio where it thinks modules are (best effort).
  pulseaudio --dump-conf 2>/dev/null | awk -F'= ' '/^dl-search-path/ {print $2; exit}' | tr ':' '
' | head -n 1
}

_pulse_has_module_file() {
  local mod="$1"
  local d; d="$(_pulse_moddir)"
  [ -n "${d:-}" ] && [ -f "$d/${mod}.so" ]
}

_start_pulse_null() {
  pulseaudio -n -F /dev/null --daemonize=yes --use-pid-file=no \
    --exit-idle-time=-1 --realtime=false --high-priority=false \
    --log-target=file:"$LOG_DIR/pulseaudio.log" \
    --load="module-native-protocol-unix socket=$PA_SOCK auth-anonymous=1" \
    --load="module-null-sink sink_name=null" \
    >>"$LOG_DIR/pulseaudio.log" 2>&1 || true
  echo "null" >"$TMPDIR/.default-sink"
}

_start_pulse_sles() {
  pulseaudio -n -F /dev/null --daemonize=yes --use-pid-file=no \
    --exit-idle-time=-1 --realtime=false --high-priority=false \
    --log-target=file:"$LOG_DIR/pulseaudio.log" \
    --load="module-native-protocol-unix socket=$PA_SOCK auth-anonymous=1" \
    --load="module-sles-sink sink_name=android_sles" \
    >>"$LOG_DIR/pulseaudio.log" 2>&1 || true
  echo "android_sles" >"$TMPDIR/.default-sink"
}

_start_pulse_aaudio() {
  pulseaudio -n -F /dev/null --daemonize=yes --use-pid-file=no \
    --exit-idle-time=-1 --realtime=false --high-priority=false \
    --log-target=file:"$LOG_DIR/pulseaudio.log" \
    --load="module-native-protocol-unix socket=$PA_SOCK auth-anonymous=1" \
    --load="module-aaudio-sink sink_name=android_aaudio rate=48000 latency=40 pm=2" \
    >>"$LOG_DIR/pulseaudio.log" 2>&1 || true
  echo "android_aaudio" >"$TMPDIR/.default-sink"
}

_pulse_wait_socket() {
  local i
  for i in $(seq 1 80); do
    [ -S "$PA_SOCK" ] && return 0
    sleep 0.1
  done
  return 1
}

_pulse_pactl() {
  PULSE_SERVER="unix:$PA_SOCK" pactl "$@"
}

_pulse_ensure_real_sink() {
  # If we booted into a null sink but AAudio/OpenSL exists, try to add it live.
  local sinks
  sinks="$(_pulse_pactl list short sinks 2>/dev/null || true)"

  if echo "$sinks" | awk '{print $2}' | grep -qx 'android_aaudio'; then
    _pulse_pactl set-default-sink android_aaudio >/dev/null 2>&1 || true
    return 0
  fi
  if echo "$sinks" | awk '{print $2}' | grep -qx 'android_sles'; then
    _pulse_pactl set-default-sink android_sles >/dev/null 2>&1 || true
    return 0
  fi

  # Try to load if module files exist (sometimes --load fails silently depending on build flags).
  if _pulse_has_module_file "module-aaudio-sink"; then
    if _pulse_pactl load-module module-aaudio-sink sink_name=android_aaudio rate=48000 latency=40 pm=2 >/dev/null 2>&1; then
      _pulse_pactl set-default-sink android_aaudio >/dev/null 2>&1 || true
      log "[OK]   PulseAudio: loaded AAudio sink (late)"
      return 0
    fi
  fi
  if _pulse_has_module_file "module-sles-sink"; then
    if _pulse_pactl load-module module-sles-sink sink_name=android_sles >/dev/null 2>&1; then
      _pulse_pactl set-default-sink android_sles >/dev/null 2>&1 || true
      log "[OK]   PulseAudio: loaded OpenSL sink (late)"
      return 0
    fi
  fi

  # If only null exists, that's still "working" audio plumbing, but no device output.
  return 1
}

start_pulseaudio() {
  log "[STEP] Starting PulseAudio..."
  pkill -9 -f "[p]ulseaudio" >/dev/null 2>&1 || true
  rm -f "$PA_SOCK" "$PA_PIDFILE" \
    "$XDG_RUNTIME_DIR/pulse/pid" "$HOME/tmp/pulse/pid" \
    "$HOME/.config/pulse/pid" "$HOME/.config/pulse/pidfile" \
    >/dev/null 2>&1 || true
  rm -rf "$HOME/tmp/pulse" >/dev/null 2>&1 || true

  # Clients use our socket; don't autospawn.
  mkdir -p "$HOME/.config/pulse"
  cat >"$HOME/.config/pulse/client.conf" <<EOF
autospawn = no
default-server = unix:$PA_SOCK
EOF

  local has_aaudio=0 has_sles=0
  _pulse_has_module_file "module-aaudio-sink" && has_aaudio=1
  _pulse_has_module_file "module-sles-sink" && has_sles=1

  if [ "${TG_PULSE_FORCE_AAUDIO:-0}" = "1" ] && [ $has_aaudio -eq 1 ]; then
    _start_pulse_aaudio; log "[OK]   PulseAudio: forced AAudio"
  elif [ "${TG_PULSE_FORCE_SLES:-0}" = "1" ] && [ $has_sles -eq 1 ]; then
    _start_pulse_sles;   log "[OK]   PulseAudio: forced OpenSL ES"
  elif [ $has_aaudio -eq 1 ]; then
    _start_pulse_aaudio; log "[OK]   PulseAudio: using AAudio"
  elif [ $has_sles -eq 1 ]; then
    _start_pulse_sles;   log "[OK]   PulseAudio: using OpenSL ES"
  else
    _start_pulse_null;   log "[WARN] PulseAudio: no AAudio/OpenSL modules; using null sink"
  fi

  export PULSE_SERVER="unix:$PA_SOCK"
  printf "export PULSE_SERVER=%q
" "$PULSE_SERVER" >"$HOME/.pulse-session"

  if ! _pulse_wait_socket; then
    log "[ERR]  PulseAudio did not create socket: $PA_SOCK"
    log "[HINT] Check: $LOG_DIR/pulseaudio.log"
    return 1
  fi

  if ! _pulse_pactl info >/dev/null 2>&1; then
    log "[ERR]  PulseAudio socket exists but pactl failed; check $LOG_DIR/pulseaudio.log"
    return 1
  fi

  # Record a best-effort pidfile for stop/status (some PA builds do not write one reliably)
  local _pa_pid
  _pa_pid="$(pgrep -n -u "$(id -u)" pulseaudio 2>/dev/null || true)"
  if [ -n "${_pa_pid:-}" ]; then printf "%s\n" "$_pa_pid" >"$PA_PIDFILE"; fi


  # Try to guarantee a non-null sink when possible.
  if _pulse_ensure_real_sink; then
    log "[OK]   PulseAudio: server=$PULSE_SERVER (real sink ready)"
  else
    log "[WARN] PulseAudio: server up, but only null sink available (no device output)"
    log "[HINT] Run: PULSE_SERVER=\"unix:$PA_SOCK\" pactl list short sinks"
  fi
}

# -------------------- XFCE --------------------
start_xfce_native() {
  log "[STEP] Starting XFCE (native)â€¦"
  [ -f "$DBUS_ADDR_FILE" ] && # shellcheck disable=SC1090
    source "$DBUS_ADDR_FILE" || true
  [ -f "$HOME/.pulse-session" ] && # shellcheck disable=SC1090
    source "$HOME/.pulse-session" || true

  ( xfce4-session >>"$LOG_DIR/xfce4_native.log" 2>&1 ) & disown
  log "[OK]   XFCE (native) start invoked."
}

start_xfce_proot_debian() {
  log "[STEP] Starting XFCE4 inside proot-distro (${PROOT_DISTRO} as ${PROOT_USER}) ..."

  local proot_cmd
  proot_cmd="$(cat <<'__TG_PROOT__'
set -e
# --- hard reset env to Debian userland (prevents Termux binary leakage) ---
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
unset PREFIX ANDROID_ROOT ANDROID_DATA ANDROID_RUNTIME_ROOT TERMUX_VERSION
hash -r

export DISPLAY=":0"
export XAUTHORITY="__XAUTH__"
export XDG_RUNTIME_DIR="/tmp/xdg-runtime-__PROOTUSER__"

# prevent Termux libs from poisoning Debian processes
unset LD_LIBRARY_PATH
unset LIBGL_DRIVERS_PATH
unset GBM_BACKENDS_PATH


mkdir -p "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/gvfsd"
chmod 700 "$XDG_RUNTIME_DIR" || true

# GUI backends
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb

# Dedicated D-Bus session bus inside proot
rm -f "$XDG_RUNTIME_DIR/bus" 2>/dev/null || true
dbus-daemon --session --fork \
  --address="unix:path=$XDG_RUNTIME_DIR/bus" \
  --print-address=1 --print-pid=1 >>"$HOME/.dbus_proot.log" 2>&1 || true
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# Use host PulseAudio socket (shared tmp)
mkdir -p "$HOME/.config/pulse"
cat >"$HOME/.config/pulse/client.conf" <<'EOF'
autospawn = no
default-server = unix:/tmp/pulse-native.sock
enable-shm = no
EOF
export PULSE_SERVER="unix:/tmp/pulse-native.sock"


export MESA_LOADER_DRIVER_OVERRIDE="zink"
export GALLIUM_DRIVER="zink"
export __GLX_VENDOR_LIBRARY_NAME="mesa"

# keep xfwm4 from trying GL compositing on startup
xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true

exec xfce4-session
__TG_PROOT__
)"
  proot_cmd="${proot_cmd//__XAUTH__/${XAUTHORITY}}"
  proot_cmd="${proot_cmd//__PROOTUSER__/${PROOT_USER}}"

  proot-distro login "$PROOT_DISTRO" --shared-tmp --user "$PROOT_USER" -- bash -lc "$proot_cmd" >>"$LOG_DIR/xfce4_proot.log" 2>&1 &
  log "[OK]   XFCE4 (proot/${PROOT_DISTRO}) start invoked."
}

# -------------------- Stack orchestration --------------------
core_stack_up() {
  doctor || die "Doctor failed."
  start_x11_strict || die "Termux:X11 failed to come up."
  start_dbus || die "D-Bus failed."
  start_pulseaudio || die "PulseAudio failed."
}

cmd_start() {
  local mode="${1:-native}"; shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --debug) DEBUG=1; shift;;
      --quiet) QUIET=1; shift;;
      *) break;;
    esac
  done

  core_stack_up

  case "$mode" in
    native)
      start_xfce_native
      log "XFCE/X11 launch sequence complete (native)."
      ;;
    debian|start-debian)
      start_xfce_proot_debian
      log "XFCE/X11 launch sequence complete (proot/$PROOT_DISTRO)."
      ;;
    *)
      die "Unknown start mode: $mode (use: start | start-debian)"
      ;;
  esac

  if [ "$DEBUG" -eq 1 ]; then
    log "[DEBUG] Live log tail (Ctrl-C to exit)"
    tail -f "$LOG_DIR"/*.log
  fi
}

cmd_stop() {
  log "[STEP] Stopping XFCE/X11 session â€¦"
  # --- Kill any proot-distro Debian session tree hard ---
  pkill -9 -f "proot.*installed-rootfs/${PROOT_DISTRO}" >/dev/null 2>&1 || true
  pkill -9 -f "proot-distro login ${PROOT_DISTRO}" >/dev/null 2>&1 || true
  pkill -9 -f "[x]fwm4|[x]fce4-session|[x]fce4-panel|[x]fdesktop|[t]hunar|[x]fsettingsd" >/dev/null 2>&1 || true
  pkill -9 -f "[x]fce4-session" >/dev/null 2>&1 || true
  pkill -9 -f "[s]tartxfce4" >/dev/null 2>&1 || true
  pkill -9 -f "termux-x11" >/dev/null 2>&1 || true
  pkill -9 -f "com.termux.x11" >/dev/null 2>&1 || true
  pkill -9 -f "[p]ulseaudio" >/dev/null 2>&1 || true
  pkill -9 -f "dbus-daemon --session" >/dev/null 2>&1 || true
  
  # --- Kill dbus-daemon by pidfile first (more reliable than pkill patterns) ---
  if [ -f "$DBUS_PIDFILE" ]; then
    DBUS_PID="$(cat "$DBUS_PIDFILE" 2>/dev/null || true)"
    if [ -n "${DBUS_PID:-}" ] && kill -0 "$DBUS_PID" 2>/dev/null; then
      kill "$DBUS_PID" 2>/dev/null || true
      sleep 0.2
      kill -9 "$DBUS_PID" 2>/dev/null || true
    fi
    rm -f "$DBUS_PIDFILE" || true
  fi

  # --- Always remove the session socket + addr file ---
  rm -f "$DBUS_SOCK" "$DBUS_ADDR_FILE" "$PA_SOCK" >/dev/null 2>&1 || true
  rm -rf "$TMPDIR/xdg-runtime-${TG_HOST_USER}" >/dev/null 2>&1 || true
  rm -rf "$TMPDIR/xdg-runtime-${PROOT_USER}"  >/dev/null 2>&1 || true
  rm -rf "$TMPDIR/xdg-runtime-droidmaster"    >/dev/null 2>&1 || true
  log "[OK]   Stopped session. Cleaned D-Bus and Pulse sockets."
  log "[INFO] Remaining related processes (should be none):"
  pgrep -fa "termux-x11|pulseaudio|dbus-daemon --session|xfce4-session" >/dev/null 2>&1 && pgrep -fa "termux-x11|pulseaudio|dbus-daemon --session|xfce4-session" || true
  log "[INFO] Remaining sockets:"
  ls -la "$TMPDIR"/pulse-native.sock "$DBUS_SOCK" 2>/dev/null || true
}

cmd_status() {
  log "=== Status / Health Check ==="
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then log "[OK]   X reachable ($DISPLAY)"; else log "[ERR]  X NOT reachable ($DISPLAY)"; fi
  if dbus_healthcheck; then log "[OK]   D-Bus healthy"; else log "[ERR]  D-Bus NOT healthy"; fi
  if [ -S "$PA_SOCK" ]; then log "[OK]   Pulse socket present ($PA_SOCK)"; else log "[ERR]  Pulse socket missing ($PA_SOCK)"; fi
  if [ -S "$PA_SOCK" ] && PULSE_SERVER="unix:$PA_SOCK" pactl info >/dev/null 2>&1; then
    log "[OK]   pactl can talk to Pulse"
  else
    log "[ERR]  pactl cannot talk to Pulse"
  fi
}

cmd_cleanlogs() {
  log "[STEP] Wiping logs in $LOG_DIR ..."
  rm -f "$LOG_DIR"/*.log "$LOG_DIR"/*.addr.sh 2>/dev/null || true
  log "[OK]   Logs wiped."
}

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME start [--debug] [--quiet]        Start native XFCE on Termux:X11
  $SCRIPT_NAME start-debian [--debug] [--quiet] Start Debian proot XFCE session (xfce4-session) on Termux:X11
  $SCRIPT_NAME stop                            Stop everything
  $SCRIPT_NAME status                          Quick health check
  $SCRIPT_NAME doctor                          Check tools/dirs
  $SCRIPT_NAME cleanlogs                       Wipe Termux-GUI logs safely
Notes:
  - Proot mode requires: proot-distro, and a Debian user (default: PROOT_USER=$PROOT_USER)
  - Proot is launched with --shared-tmp; therefore Termux \$PREFIX/tmp == proot /tmp
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    start)        cmd_start native "$@";;
    start-debian) cmd_start debian "$@";;
    stop)         cmd_stop;;
    status)       cmd_status;;
    doctor)       doctor;;
    cleanlogs)    cmd_cleanlogs;;
    ""|help|-h|--help) usage;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
