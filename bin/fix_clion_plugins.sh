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

CONF_DIR="$HOME/.config/JetBrains/CLion2025.1"
DISABLED="$CONF_DIR/disabled_plugins.txt"
mkdir -p "$CONF_DIR"
touch "$DISABLED"

for pid in \
  "org.jetbrains.plugins.clion.radler" \
  "intellij.rider.cpp.debugger" \
  "intellij.rider.plugins.clion.radler.cwm" \
  "com.jetbrains.codeWithMe" \
; do
  if ! grep -qx "$pid" "$DISABLED"; then
    echo "$pid" >> "$DISABLED"
    echo "[fix-plugins] disabled $pid"
  fi
done

for d in rider-plugins-clion-radler-cwm rider-plugins-cpp-debugger; do
  if [ -d "$IDE_DIR/plugins/$d" ]; then
    echo "[fix-plugins] removing $IDE_DIR/plugins/$d"
    rm -rf "$IDE_DIR/plugins/$d"
  fi
done
echo "[fix-plugins] done."
