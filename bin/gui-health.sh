#!/data/data/com.termux/files/usr/bin/bash
# ---- toolchain/termux prelude ----
if [ -z "$__TOOLCHAIN_PRELUDE" ]; then
  __TOOLCHAIN_PRELUDE=1
  : ${TMP:="$HOME$TMP"}; mkdir -p -- "$TMP"
  # minimal PATH glue (keep short, user can extend in ~/.zshrc)
  if [ -d "$HOME/opt/toolchain/aarch64-linux-android/bin" ]; then
    case ":$PATH:" in *":$HOME/opt/toolchain/aarch64-linux-android/bin:"*) ;; 
      *) PATH="$HOME/opt/toolchain/aarch64-linux-android/bin:$PATH";;
    esac
  fi
fi
# ---- end prelude ----

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
TMPDIR="${TMPDIR:-$HOME$TMP}"
XSOCK="$TMPDIR/.X11-unix/X0"

echo "=== GUI Health @ $(date) ==="
echo "DISPLAY=${DISPLAY:-<unset>}"
if [ -S "$XSOCK" ]; then
  echo "[OK] X11 socket exists: $XSOCK"
else
  echo "[ERR] X11 socket missing: $XSOCK"
fi

if pgrep -f "^dbus-daemon" >/dev/null; then
  echo "[OK] dbus-daemon running (session)"
else
  echo "[ERR] dbus-daemon NOT running"
fi

if pgrep -f "^pulseaudio" >/dev/null; then
  echo "[OK] pulseaudio running"
else
  echo "[WARN] pulseaudio not running"
fi

if pgrep -f "^xfce4-session" >/dev/null; then
  echo "[OK] xfce4-session running"
else
  echo "[WARN] xfce4-session not running"
fi

