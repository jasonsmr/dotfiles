# Reestablish environment for aarch64 Android GCC-on-NDK
# Safe for Termux zsh/bash: no -e, no pipefail, no globs.

# --- paths you already use ---
export PREFIX="$HOME/opt/toolchain/aarch64-linux-android"
export BUILD="$HOME/build/gcc-android-stage1"
export TRIPLE="aarch64-linux-android"
export API=28

# NDK (aarch64 host prebuilt)
export NDK_ROOT="$HOME/opt/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64"
export NDK_SYSROOT="$NDK_ROOT/sysroot"

# Your stage1 GCC
export GCC="$PREFIX/bin/${TRIPLE}-gcc"

# Host libs for cc1 (gmp/mpfr/mpc)
export LD_LIBRARY_PATH="$HOME/opt/host-libs/lib:${LD_LIBRARY_PATH-}"

# Ensure our toolchain bin shows up before others
case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) export PATH="$PREFIX/bin:$PATH" ;;
esac

# Kill include-path pollution that previously dragged x86_64 headers
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH ANDROID_NDK_HOME ANDROID_NDK_ROOT

# Quick sanity: show key bits (no failure if missing)
echo "NDK_SYSROOT=$NDK_SYSROOT"
echo "GCC=$GCC"
command -v "$GCC" || echo "!! GCC not on PATH yet: $GCC"
