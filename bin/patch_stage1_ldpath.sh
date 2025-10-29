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

SCRIPT="$HOME/build/scripts/20_build_gcc_android_stage1.sh"
BAK="$SCRIPT.bak.$(date +%Y%m%d_%H%M%S)"
cp -f "$SCRIPT" "$BAK"

# Insert LD_LIBRARY_PATH export right after NDK_SYSROOT= line
# Path we want: $NDK_SYSROOT/usr/lib/$TARGET_TRIPLE/$ANDROID_API
TMP="$SCRIPT.tmp.$$"
awk '
  BEGIN{done=0}
  {print}
  /NDK_SYSROOT=/ && !done {
    print "export LD_LIBRARY_PATH=\"${NDK_SYSROOT}/usr/lib/${TARGET_TRIPLE}/${ANDROID_API}:${LD_LIBRARY_PATH:-}\""
    done=1
  }
' "$SCRIPT" > "$TMP"
mv "$TMP" "$SCRIPT"
chmod +x "$SCRIPT"

echo "Patched LD_LIBRARY_PATH for libc++_shared lookup."
echo "Backup saved: $BAK"

# clean stage1 so it reconfigures
rm -rf "$HOME/toolchain-work/build/gcc-android-stage1" || true

# rebuild
ninja -C "$HOME/build/out" -v android-toolchain
