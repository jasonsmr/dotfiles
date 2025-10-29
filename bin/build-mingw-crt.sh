#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
[[ "${TRACE-0}" = 1 ]] && set -x

# Roots
export HOME=${HOME:-/data/data/com.termux/files/home}
ROOT="$HOME/opt"
SRC="$HOME/src"
BUILD="$HOME/build"
LOGDIR="$HOME/logs/cross"
XPREFIX="$ROOT/toolchain"
T64="${T64-x86_64-w64-mingw32}"
T32="${T32-i686-w64-mingw32}"
TARGETS="${TARGETS-$T64 $T32}"

# Host toolchain (Termux)
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

# Find mingw-w64 source
for CAND in "$SRC/mingw-w64" "$SRC/mingw-w64-11.0.1" "$SRC/mingw-w64-v11.0.1"; do
  [[ -d "$CAND" ]] && MINGW_SRC="$CAND" && break || true
done
[[ -n "${MINGW_SRC-}" ]] || die "mingw-w64 sources not found"

for T in $TARGETS; do
  SYSROOT="$XPREFIX/$T"              # toolchain root for this target
  T_SYS="$SYSROOT/$T"                # actual sysroot dirs live here
  CRT_BUILD="$BUILD/mingw-crt-$T"

  # Make sure headers are present
  if [[ ! -f "$T_SYS/include/_mingw_mac.h" ]]; then
    die "Missing headers in $T_SYS/include (run your header install step first)"
  fi

  # Use target compilers and point them at the sysroot explicitly
  export PATH="$SYSROOT/bin:$PATH"
  export CC="$HOST_BIN/clang --target=$T"
  export CXX="$HOST_BIN/clang++ --target=$T"
  # Make sysroot + includes/libs visible to clang
  export CPPFLAGS="--sysroot=$SYSROOT -I$T_SYS/include"
  export LDFLAGS="--sysroot=$SYSROOT -L$T_SYS/lib"
  # dlltool for some rules (use LLVM; GNU is fine too if you later add it)
  case "$T" in
    x86_64-w64-mingw32) MCH="i386:x86-64" ;;
    i686-w64-mingw32)   MCH="i386" ;;
    *) die "unknown target $T";;
  esac
  export DLLTOOL="$HOST_BIN/llvm-dlltool -m $MCH"

  # Fresh out-of-tree build
  rm -rf "$CRT_BUILD" && mkdir -p "$CRT_BUILD"

  msg "=== $T : configure CRT ==="
  pushd "$CRT_BUILD" >/dev/null

  # NOTE: CRT’s configure ignores --enable-{shared,static}; it decides itself.
  # The important bit is: --with-sysroot points at $SYSROOT, and our CPPFLAGS/LDFLAGS above.
  bash "$MINGW_SRC/mingw-w64-crt/configure" \
      --host="$T" \
      --prefix="$T_SYS" \
      --with-sysroot="$SYSROOT"

  msg "=== $T : make CRT ==="
  make -j1

  msg "=== $T : install CRT ==="
  make -j1 install

  popd >/dev/null
done

msg "Done. CRT installed into $XPREFIX/<target>/<target>/{include,lib*}"
