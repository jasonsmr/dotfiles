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

# env sanity
echo $PATH
cd $HOME/play/android-hello
command -v meson ninja clang pkg-config

# cross sanity
choose android --ndk latest --api 28 --mode cross --persist
meson setup build --wipe --cross-file ~/.config/meson/cross/_current-ndk-cross.ini
meson compile -C build && ./build/hello_ndk

# hybrid sanity (Termux .pc OFF)
choose android --ndk latest --api 28 --mode hybrid --persist
meson setup build-hybrid --wipe --cross-file ~/.config/meson/cross/_current-ndk-hybrid.ini
meson compile -C build-hybrid && ./build-hybrid/hello_ndk

# hybrid + one real dep via .pc (only when needed)
hybrid-pc-on
meson setup build-hybrid-pc --wipe --cross-file ~/.config/meson/cross/_current-ndk-hybrid.ini
meson compile -C build-hybrid-pc
hybrid-pc-off
