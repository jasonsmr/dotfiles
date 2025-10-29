#!/system/bin/sh
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

LOG="$HOME/logs/build/android/make-stage1-$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$(dirname "$LOG")"

echo "== cleaning stage1 =="
rm -rf "$BD" || true
mkdir -p "$BD"

echo "== kicking ninja to (re)configure =="
# let your existing script re-run configure
ninja -C "$HOME/build/out" -v android-toolchain || true

echo "== make all-gcc with full verbosity =="
if [ -d "$BD" ]; then
  ( set -x
    make -C "$BD" V=1 all-gcc
  ) >"$LOG" 2>&1 || true
else
  echo "Stage1 build dir missing: $BD" | tee "$LOG"
fi

echo "== FIRST error line =="
grep -nE "(^|\s)error[: ]" "$LOG" | head -n 1 || true
echo "== LOG saved: $LOG =="
