#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
[[ "${TRACE-0}" = 1 ]] && set -x

export HOME=${HOME:-/data/data/com.termux/files/home}
ROOT="$HOME/opt"
SRC="$HOME/src"
BUILD="$HOME/build"
LOGDIR="$HOME/logs/cross"
XPREFIX="$ROOT/toolchain"
HOSTLIB="$ROOT/host-libs"
T64="${T64-x86_64-w64-mingw32}"
T32="${T32-i686-w64-mingw32}"
TARGETS="${TARGETS-$T64 $T32}"

# Host toolchain
HOST_BIN="/data/data/com.termux/files/usr/bin"
export CC="$HOST_BIN/clang"
export CXX="$HOST_BIN/clang++"
export AR="$HOST_BIN/ar"
export RANLIB="$HOST_BIN/ranlib"
export NM="$HOST_BIN/nm"
export LD="$HOST_BIN/ld.lld"
export PATH="$HOST_BIN:$HOME/bin"

# GMP/MPFR/MPC/ISL for building GCC (you already built & installed to host-libs)
export PKG_CONFIG_PATH="$HOSTLIB/lib/pkgconfig"
export LD_LIBRARY_PATH="$HOSTLIB/lib:${LD_LIBRARY_PATH-}"
export CFLAGS="-I$HOSTLIB/include ${CFLAGS-}"
export CXXFLAGS="-I$HOSTLIB/include ${CXXFLAGS-}"
export LDFLAGS="-L$HOSTLIB/lib ${LDFLAGS-}"

mkdir -p "$SRC" "$BUILD" "$LOGDIR"

die(){ printf '!! %s\n' "$*" >&2; exit 1; }
msg(){ printf '>> %s\n' "$*"; }

# Choose your GCC source folder (prefer 14.1.0 if present)
for CAND in "$SRC/gcc-14.1.0" "$SRC/gcc-13.2.0"; do
  [[ -d "$CAND" ]] && GCCSRC="$CAND" && break || true
done
[[ -n "${GCCSRC-}" ]] || die "GCC sources not found in $SRC (expected gcc-14.1.0/ or gcc-13.2.0/)"

# Ensure prerequisite in-tree symlinks for GCC’s bundled deps (optional if using system libs)
pushd "$GCCSRC" >/dev/null
./contrib/download_prerequisites || true
popd >/dev/null

for T in $TARGETS; do
  SYSROOT="$XPREFIX/$T/$T"
  INST="$XPREFIX/$T"
  GBUILD="$BUILD/gcc-$T"
  rm -rf "$GBUILD" && mkdir -p "$GBUILD"

  msg "=== $T : configure GCC (C,C++) ==="
  pushd "$GBUILD" >/dev/null
  bash "$GCCSRC/configure" \
    --build=aarch64-unknown-linux-android \
    --host=aarch64-unknown-linux-android \
    --target="$T" \
    --prefix="$INST" \
    --with-sysroot="$SYSROOT" \
    --disable-multilib \
    --disable-nls \
    --enable-languages=c,c++ \
    --enable-threads=posix \
    --disable-libsanitizer \
    --disable-libquadmath \
    --disable-libgomp \
    --disable-libitm \
    --disable-libssp \
    --with-gmp="$HOSTLIB" --with-mpfr="$HOSTLIB" --with-mpc="$HOSTLIB" --with-isl="$HOSTLIB"

  msg "=== $T : make GCC ==="
  make -j1

  msg "=== $T : install GCC ==="
  make -j1 install
  popd >/dev/null
done

msg "Done. GCC installed under: $XPREFIX/{x86_64-w64-mingw32,i686-w64-mingw32}"
msg "Try:   $XPREFIX/x86_64-w64-mingw32/bin/x86_64-w64-mingw32-gcc -v"
