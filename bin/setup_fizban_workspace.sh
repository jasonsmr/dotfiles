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


TS="$(date +%Y%m%d-%H%M%S)"
BK="$HOME/backup/fizban-$TS"
mkdir -p "$BK" "$HOME/src" "$HOME/build" "$HOME/opt" "$HOME/logs"

note() { printf "[fizban] %s\n" "$*"; }

# 1) Android SDK/NDK sanity (non-invasive)
SDK="$HOME/opt/android-sdk"
NDK="${ANDROID_NDK_HOME:-$HOME/opt/android-sdk/ndk/27.1.12297006}"
if [ ! -d "$SDK" ]; then
  note "Android SDK not found at $SDK (ok). You can install later with sdkmanager in Termux."
fi
if [ ! -d "$NDK" ]; then
  note "NDK not found at $NDK (ok). Point ANDROID_NDK_HOME to your NDK if needed."
fi

# 2) Lightweight shell include (opt-in PATH helpers only; no LD_LIBRARY_PATH)
INC="$HOME/.shell_rc_content"
if [ -f "$INC" ]; then cp -a "$INC" "$BK/.shell_rc_content.bak"; fi
cat > "$INC" <<EOF
# --- Fizban shell helpers (safe PATH only) ---
export ANDROID_HOME="${ANDROID_HOME:-$SDK}"
export ANDROID_SDK_ROOT="\${ANDROID_SDK_ROOT:-$SDK}"
export ANDROID_NDK_HOME="\${ANDROID_NDK_HOME:-$NDK}"

# Add SDK tools if present
[ -d "\$ANDROID_HOME/platform-tools" ] && PATH="\$ANDROID_HOME/platform-tools:\$PATH"
[ -d "\$ANDROID_HOME/emulator" ] && PATH="\$ANDROID_HOME/emulator:\$PATH"
[ -d "\$ANDROID_HOME/cmdline-tools/latest/bin" ] && PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"
# Avoid adding build-tools bins globally to prevent accidental tool picking
# You can use sdkmanager/gradle to invoke them per-project
# ---------------------------------------------------------
EOF
note "Updated $INC (backup at $BK/.shell_rc_content.bak)."

# 3) CLion env wrapper to tail logs conveniently
cat > "$HOME/bin/clion-env.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
LOG="$HOME/.cache/JetBrains/CLion2025.1/log/idea.log"
echo "[clion-env] launcher: $HOME/bin/clion-termux"
echo "[clion-env] log: $LOG"
exec "$HOME/bin/clion-termux" "$@"
EOF
chmod +x "$HOME/bin/clion-env.sh"

# 4) Plugin sanity fixer (idempotent)
cat > "$HOME/bin/fix_clion_plugins.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
IDE_DIR="${IDE_DIR:-$HOME/opt/jetbrains/clion-2025.1.3}"
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
EOF
chmod +x "$HOME/bin/fix_clion_plugins.sh"

note "Fizban workspace refreshed."
