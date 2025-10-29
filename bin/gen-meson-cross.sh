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

case "${1:-}" in
  ndk-cross) fizban_load_persisted; cp -f "$HOME/.config/meson/cross/_current-ndk-cross.ini"  "$HOME/.config/meson/cross/active.ini"; echo "[gen-meson] active=ndk-cross";;
  ndk-hybrid) fizban_load_persisted; cp -f "$HOME/.config/meson/cross/_current-ndk-hybrid.ini" "$HOME/.config/meson/cross/active.ini"; echo "[gen-meson] active=ndk-hybrid";;
  --help|-h|"") cat <<H
gen-meson-cross.sh — write a resolved Meson cross file from your live env.

Usage:
  gen-meson-cross.sh ndk-cross
  gen-meson-cross.sh ndk-hybrid

Then:
  meson setup build --cross-file ~/.config/meson/cross/active.ini
H
  ;;
esac
