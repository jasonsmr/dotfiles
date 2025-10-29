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

# Host
export DISPLAY="${DISPLAY:-:0}"
export PULSE_SERVER="${PULSE_SERVER:-unix:$PREFIX$HOME$TMP/pulse-native.sock}"

# Box64 toggles
export BOX64_DYNAREC="${BOX64_DYNAREC:-1}"
export BOX64_VULKAN="${BOX64_VULKAN:-1}"
export BOX64_LOG="${BOX64_LOG:-0}"

# Paths
BOX64="$HOME/opt/box64/bin/box64"
GUEST64="$HOME/opt/guest-root/x86_64"
GUEST32="$HOME/opt/guest-root/i386"
WINE64_DIR="$HOME/opt/guest-root/wine-x64"
WINE32_DIR="$HOME/opt/guest-root/wine-x86"

# Search order: wine64 and its libs first, then guest libs
export BOX64_PATH="$WINE64_DIR:$GUEST64/usr/bin:$GUEST64/bin"
export BOX64_LD_LIBRARY_PATH="$WINE64_DIR:$GUEST64/lib64:$GUEST64/usr/lib64:$GUEST64/lib:$GUEST64/usr/lib"

# If your Wine requires both 64/32 loader paths in WoW64 mode, add WINE32_DIR to LD path too:
export BOX64_LD_LIBRARY_PATH="$BOX64_LD_LIBRARY_PATH:$WINE32_DIR:$GUEST32/lib:$GUEST32/usr/lib"

# Wine prefix (override per-app if you like)
export WINEPREFIX="${WINEPREFIX:-$HOME/games/prefixes/default}"

# Typical DXVK overrides (only take effect once DXVK DLLs are in place in the prefix)
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d9,d3d10core,d3d11,dxgi=b;winemenubuilder.exe=d}"

# Caller can pass "winecfg", "notepad", or any EXE
if [ $# -eq 0 ]; then
  set -- winecfg
fi

exec "$BOX64" "$WINE64_DIR/bin/wine64" "$@"
