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

if [ ! -d "$CDIR" ]; then
  echo "libcody dir not present yet (stage1 not at that point)."
  exit 0
fi
CFG="$CDIR/config.log"
if [ ! -f "$CFG" ]; then
  echo "libcody/config.log not found yet."
  exit 0
fi

echo "==== libcody/config.log: errors ===="
grep -n "configure: error:" "$CFG" || { echo "no errors"; exit 0; }
echo
echo "-- tail (80) --"
tail -n 80 "$CFG"
echo
echo "If you still see 'libc++_shared.so not found', then LD_LIBRARY_PATH didn’t propagate."
