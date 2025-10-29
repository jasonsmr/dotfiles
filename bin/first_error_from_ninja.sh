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

if [ ! -f "$LOG" ]; then
  echo "Log not found: $LOG"
  exit 1
fi
echo "NINJA first errorish line:"
grep -nE '(^|\s)error[: ]' "$LOG" | head -n 1
LNO="$(grep -nE '(^|\s)error[: ]' "$LOG" | head -n 1 | cut -d: -f1 || true)"
if [ -n "${LNO:-}" ]; then
  LO=$((LNO-20)); [ $LO -lt 1 ] && LO=1
  HI=$((LNO+40))
  echo
  echo "Context around $LNO:"
  sed -n "${LO},${HI}p" "$LOG"
fi
