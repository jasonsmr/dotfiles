#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
[[ "${TRACE-0}" = 1 ]] && set -x

export HOME=${HOME:-/data/data/com.termux/files/home}
ROOT="$HOME/opt"
SRC="$HOME/src"
BUILD="$HOME/build"
LOGDIR="$HOME/logs/cross"
XPREFIX="$ROOT/toolchain"
T64="${T64-x86_64-w64-mingw32}"
T32="${T32-i686-w64-mingw32}"
TARGETS="${TARGETS-$T64 $T32}"

HOST_BIN="/data/data/com.termux/files/usr/bin"
export CC="$HOST_BIN/clang"
export CXX="$HOST_BIN/clang++"
export AR="$HOST_BIN/ar"
export RANLIB="$HOST_BIN/ranlib"
export NM="$HOST_BIN/nm"
export LD="$HOST_BIN/ld.lld"
export PATH="$HOST_BIN:$HOME/bin"

mkdir -p "$SRC" "$BUILD" "$LOGDIR"

die(){ printf '!! %s\n' "$*" >&2; exit 1; }
msg(){ printf '>> %s\n' "$*"; }

for CAND in "$SRC/mingw-w64" "$SRC/mingw-w64-11.0.1" "$SRC/mingw-w64-v11.0.1"; do
  [[ -d "$CAND" ]] && MINGW_SRC="$CAND" && break || true
done
[[ -n "${MINGW_SRC-}" ]] || die "mingw-w64 sources not found"

for T in $TARGETS; do
  SYSROOT="$XPREFIX/$T/$T"
  PTH_BUILD="$BUILD/winpthreads-$T"
  rm -rf "$PTH_BUILD" && mkdir -p "$PTH_BUILD"

  msg "=== $T : configure winpthreads ==="
  pushd "$PTH_BUILD" >/dev/null
  bash "$MINGW_SRC/mingw-w64-libraries/winpthreads/configure" \
    --host="$T" \
    --prefix="$SYSROOT" \
    --with-sysroot="$SYSROOT" \
    --enable-shared --enable-static
  msg "=== $T : make winpthreads ==="
  make -j1
  msg "=== $T : install winpthreads ==="
  make -j1 install
  popd >/dev/null
done

msg "Done. winpthreads installed into each sysroot (libs and headers)."
