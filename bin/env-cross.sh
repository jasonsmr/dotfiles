#!/data/data/com.termux/files/usr/bin/bash
# Minimal, robust env for cross builds on Termux (Android/aarch64 host)

# --- roots ---
export HOME="${HOME:-/data/data/com.termux/files/home}"
export ROOT="$HOME/opt"
export SRC="$HOME/src"
export BUILD="$HOME/build"
export WRK="$HOME/work"
mkdir -p "$ROOT" "$SRC" "$BUILD" "$WRK"

# --- host libs for GCC frontends you built earlier (mpfr/mpc/gmp) ---
export HOSTLIB="$ROOT/host-libs/lib"
# Keep any existing entries and avoid duplicates:
case ":${LD_LIBRARY_PATH-}:" in
  *":$HOSTLIB:"*) : ;;
  *) export LD_LIBRARY_PATH="$HOSTLIB${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}";;
esac

# --- NDK (not used for binutils host tools, but we keep them for later steps) ---
export NDK_ROOT="$ROOT/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64"
export NDK_SYSROOT="$NDK_ROOT/sysroot"
export API="${API:-28}"

# --- host toolchain: force Termux compilers/binutils for any host-built tools ---
HOST_BIN="/data/data/com.termux/files/usr/bin"
export CC="$HOST_BIN/clang"
export CXX="$HOST_BIN/clang++"
export AR="$HOST_BIN/ar"
export RANLIB="$HOST_BIN/ranlib"
export NM="$HOST_BIN/nm"
export LD="$HOST_BIN/ld.lld"
export STRIP="$HOST_BIN/strip"
export PKG_CONFIG="$HOST_BIN/pkg-config"

# Clean PATH to keep NDK/other clangs out while building host tools
export PATH="$HOST_BIN:$HOME/bin"

# --- cross prefixes/install roots ---
export XPREFIX="$ROOT/toolchain"
export T64="x86_64-w64-mingw32"
export T32="i686-w64-mingw32"

# --- make parallelism (Termux on-device builds can be RAM-limited) ---
export J1="-j1"

# Helpful echo for “. env-cross.sh” UX
echo "SRC=$SRC"
echo "BUILD=$BUILD"
echo "XPREFIX=$XPREFIX"
echo "PATH=$PATH"
