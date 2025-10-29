#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

TRACE=${TRACE-0}
[[ "$TRACE" = 1 ]] && set -x

# --- env (must match your env-cross.sh) ---
export HOME=${HOME:-/data/data/com.termux/files/home}
ROOT="$HOME/opt"
SRC="$HOME/src"
BUILD="$HOME/build"
LOGDIR="$HOME/logs/cross"
XPREFIX="$ROOT/toolchain"
T64="${T64-x86_64-w64-mingw32}"
T32="${T32-i686-w64-mingw32}"
TARGETS="${TARGETS-$T64 $T32}"

# Host tools: force Termux clang toolchain for building host parts
HOST_BIN="/data/data/com.termux/files/usr/bin"
export CC="$HOST_BIN/clang"
export CXX="$HOST_BIN/clang++"
export AR="$HOST_BIN/ar"
export RANLIB="$HOST_BIN/ranlib"
export NM="$HOST_BIN/nm"
export LD="$HOST_BIN/ld.lld"
export PKG_CONFIG="$HOST_BIN/pkg-config"
export PATH="$HOST_BIN:$HOME/bin"

mkdir -p "$SRC" "$BUILD" "$LOGDIR"

die(){ printf '!! %s\n' "$*" >&2; exit 1; }
msg(){ printf '>> %s\n' "$*"; }

# Find mingw-w64 source dir (you have several; prefer unpacked folder)
for CAND in "$SRC/mingw-w64" "$SRC/mingw-w64-11.0.1" "$SRC/mingw-w64-v11.0.1"; do
  [[ -d "$CAND" ]] && MINGW_SRC="$CAND" && break || true
done
[[ -n "${MINGW_SRC-}" ]] || die "mingw-w64 sources not found in $SRC (expected mingw-w64*/)"

for T in $TARGETS; do
  SYSROOT="$XPREFIX/$T/$T"
  HDR_BUILD="$BUILD/mingw-headers-$T"
  mkdir -p "$SYSROOT" "$HDR_BUILD"

  msg "=== $T : configure headers ==="
  rm -rf "$HDR_BUILD" && mkdir -p "$HDR_BUILD"
  pushd "$HDR_BUILD" >/dev/null

  bash "$MINGW_SRC/mingw-w64-headers/configure" \
    --host="$T" \
    --prefix="$SYSROOT" \
    --enable-secure-api \
    --enable-sdk=all

  msg "=== $T : make install headers ==="
  make -j1 install

  popd >/dev/null
done

msg "Done. Headers installed in: $XPREFIX/{x86_64-w64-mingw32,i686-w64-mingw32}/*/include"
