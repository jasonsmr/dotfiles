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
export AR="$HOST_BIN/ar"
export RANLIB="$HOST_BIN/ranlib"
export NM="$HOST_BIN/nm"
export LD="$HOST_BIN/ld.lld"
export PATH="$HOST_BIN:$HOME/bin"

mkdir -p "$SRC" "$BUILD" "$LOGDIR"

die(){ printf '!! %s\n' "$*" >&2; exit 1; }
msg(){ printf '>> %s\n' "$*"; }

# Pick mingw-w64 source tree
for CAND in "$SRC/mingw-w64" "$SRC/mingw-w64-11.0.1" "$SRC/mingw-w64-v11.0.1"; do
  [[ -d "$CAND" ]] && MINGW_SRC="$CAND" && break || true
done
[[ -n "${MINGW_SRC-}" ]] || die "mingw-w64 sources not found"

# If someone accidentally configured in-tree earlier, clean it to avoid
# "source directory already configured" from autoconf.
make -C "$MINGW_SRC/mingw-w64-libraries/winpthreads" distclean >/dev/null 2>&1 || true
rm -f "$MINGW_SRC/mingw-w64-libraries/winpthreads"/config.cache config.status Makefile >/dev/null 2>&1 || true

for T in $TARGETS; do
  SYSROOT="$XPREFIX/$T"
  T_SYS="$SYSROOT/$T"

  [[ -f "$T_SYS/include/_mingw_mac.h" ]] || die "Missing headers in $T_SYS/include (install headers first)"
  [[ -f "$T_SYS/lib/libmingwex.a" ]] || echo "!! Warning: CRT libs not found in $T_SYS/lib yet"

  # toolchain + flags
  export PATH="$SYSROOT/bin:$PATH"
  export CC="$HOST_BIN/clang --target=$T"
  export CXX="$HOST_BIN/clang++ --target=$T"
  export CPPFLAGS="--sysroot=$SYSROOT -I$T_SYS/include"
  export LDFLAGS="--sysroot=$SYSROOT -L$T_SYS/lib"

  # dlltool fallback (LLVM)
  case "$T" in
    x86_64-w64-mingw32) MCH="i386:x86-64" ;;
    i686-w64-mingw32)   MCH="i386" ;;
    *) die "unknown target $T";;
  esac
  export DLLTOOL="$HOST_BIN/llvm-dlltool -m $MCH"

  # windres / RC: prefer GNU $T-windres if you add it; otherwise LLVM.
  if command -v "$T-windres" >/dev/null 2>&1; then
    export RC="$T-windres -I$T_SYS/include"
    export WINDRES="$T-windres -I$T_SYS/include"
  else
    export RC="$HOST_BIN/llvm-windres --target=$T -I$T_SYS/include"
    export WINDRES="$HOST_BIN/llvm-windres --target=$T -I$T_SYS/include"
  fi

  msg "=== $T : winpthreads configure ==="
  PTH_BUILD="$BUILD/winpthreads-$T"
  rm -rf "$PTH_BUILD" && mkdir -p "$PTH_BUILD"
  pushd "$PTH_BUILD" >/dev/null

  # Pass RC/WINDRES explicitly so libtool knows the program to invoke.
  RC="$RC" WINDRES="$WINDRES" \
  bash "$MINGW_SRC/mingw-w64-libraries/winpthreads/configure" \
      --host="$T" \
      --prefix="$T_SYS" \
      --with-sysroot="$SYSROOT" \
      --enable-shared --enable-static

  msg "=== $T : make winpthreads ==="
  make -j1

  msg "=== $T : install winpthreads ==="
  make -j1 install

  popd >/dev/null
done

msg "Done. winpthreads installed into $XPREFIX/<target>/<target>/{include,lib*}"
