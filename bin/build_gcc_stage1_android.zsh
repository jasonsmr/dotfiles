#!/data/data/com.termux/files/usr/bin/env zsh
# No set -e / pipefail; keep shell alive and log errors.

log(){ print -r -- "\n==> $*"; }
try(){ print -r -- "+ $*"; "$@"; rc=$?; (( rc == 0 )) || print -r -- "!! failed ($rc)"; return $rc; }

# --- Termux-safe temp
: ${TMP:="$HOME/tmp"}; mkdir -p -- "$TMP"

# --- NDK/Toolchain env (matches your working setup)
export TRIPLE="${TRIPLE:-aarch64-linux-android}"
export API="${API:-28}"
export NDK="${NDK:-$HOME/opt/android-sdk/ndk/latest}"
export PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-aarch64"
export SYSROOT="$PREBUILT/sysroot"
export PREFIX="$HOME/opt/toolchain/$TRIPLE"
export PATH="$PREFIX/bin:$PREBUILT/bin:$PATH"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-$PREFIX/lib:$PREFIX/lib64:$PREFIX/libexec:$PREFIX/$TRIPLE/lib}"

# --- source/build/log dirs
SRC_GCC="${SRC_GCC:-$HOME/src/gcc-13.2.0}"
BUILD="${BUILD:-$HOME/build/gcc-android-stage1}"
LOGDIR="$HOME/logs"; mkdir -p -- "$BUILD" "$LOGDIR"

log "Using TRIPLE=$TRIPLE API=$API"
log "SYSROOT=$SYSROOT"
log "PREFIX=$PREFIX"
log "TMP=$TMP"

if [ ! -d "$SRC_GCC" ]; then
  print -r -- "!! GCC sources not found at $SRC_GCC"
  print -r -- "   Extract gcc-13.2.0 to $SRC_GCC or set SRC_GCC=..."
  return 0
fi

# --- tool selections (host clang + target binutils you built)
export CC="clang"
export CXX="clang++"
export AR="$TRIPLE-ar"
export AS="$TRIPLE-as"
export RANLIB="$TRIPLE-ranlib"
export LD="$TRIPLE-ld"
export NM="$TRIPLE-nm"
export STRIP="$TRIPLE-strip"

# --- find GMP/MPFR/MPC (prefer your local builds)
# We accept either "installed prefix" style (has include/ and lib/) or Termux host libs as last resort.
typeset -a CANDS
CANDS=(
  "$HOME/build/gmp-build"   "$HOME/build/mpfr-build"   "$HOME/build/mpc-build"
  "$HOME/opt/host-libs"     "$PREFIX"                  "$PREFIX/$TRIPLE"
  "$HOME/opt"               "$HOME"
)

find_libroot(){
  local hdr="$1" so="$2" p
  for p in "${CANDS[@]}"; do
    if [ -f "$p/include/$hdr" ] && ( [ -e "$p/lib/$so" ] || ls "$p/lib/"lib${hdr%%.*}*.so* "$p/lib/"lib${hdr%%.*}*.a* >/dev/null 2>&1 ); then
      print -r -- "$p"
      return 0
    fi
  done
  return 1
}

GMP_ROOT="$(  find_libroot gmp.h   libgmp.so   )"
MPFR_ROOT="$( find_libroot mpfr.h  libmpfr.so  )"
MPC_ROOT="$(  find_libroot mpc.h   libmpc.so   )"

if [ -z "$GMP_ROOT" ] || [ -z "$MPFR_ROOT" ] || [ -z "$MPC_ROOT" ]; then
  print -r -- "!! Missing dev libs:"
  [ -z "$GMP_ROOT" ]  && print -r -- "   - GMP headers/lib not found"
  [ -z "$MPFR_ROOT" ] && print -r -- "   - MPFR headers/lib not found"
  [ -z "$MPC_ROOT" ]  && print -r -- "   - MPC headers/lib not found"
  print -r -- ">> Fix options (pick one):"
  print -r -- "   A) Point to your prefixes: export GMP_ROOT=/path MPFR_ROOT=/path MPC_ROOT=/path and rerun."
  print -r -- "   B) Vendor sources: place gmp/, mpfr/, mpc/ source dirs inside $SRC_GCC and rerun."
  print -r -- "   C) (Last resort) host install: pkg install gmp mpfr libmpc"
  return 0
fi

log "Using GMP=$GMP_ROOT MPFR=$MPFR_ROOT MPC=$MPC_ROOT"

# Help GCC find the headers/libs at configure time
export CPPFLAGS="-I$GMP_ROOT/include -I$MPFR_ROOT/include -I$MPC_ROOT/include ${CPPFLAGS:-}"
export LDFLAGS="-L$GMP_ROOT/lib -L$MPFR_ROOT/lib -L$MPC_ROOT/lib ${LDFLAGS:-}"

# Keep GCC’s target-flags lean
export CFLAGS_FOR_TARGET="-O2 -pipe --sysroot=$SYSROOT"
export CXXFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET"
export LDFLAGS_FOR_TARGET="--sysroot=$SYSROOT"

# --- configure args
typeset -a CFG
CFG=(
  --target="$TRIPLE"
  --prefix="$PREFIX"
  --with-sysroot="$SYSROOT"
  --with-native-system-header-dir=/usr/include
  --with-gmp="$GMP_ROOT"
  --with-mpfr="$MPFR_ROOT"
  --with-mpc="$MPC_ROOT"
  --disable-nls
  --disable-multilib
  --enable-languages=c
  --disable-libsanitizer
  --disable-libquadmath
  --disable-libgomp
  --disable-libatomic
  --disable-libitm
  --disable-libssp
  --enable-initfini-array
)

log "Configuring stage1 in $BUILD"
cd "$BUILD" || return 0

if [ ! -f Makefile ]; then
  try "$SRC_GCC/configure" "${CFG[@]}" >"$LOGDIR/gcc-stage1-configure.log" 2>&1 \
  || { print -r -- "!! see $LOGDIR/gcc-stage1-configure.log"; return 0; }
else
  log "Makefile already present; skipping configure"
fi

log "Building all-gcc + all-target-libgcc (this is the long step)"
try make -j"$(nproc)" all-gcc all-target-libgcc >"$LOGDIR/gcc-stage1-build.log" 2>&1 \
|| print -r -- "!! build had errors (see $LOGDIR/gcc-stage1-build.log)"

log "Installing stage1 bits"
try make install-gcc install-target-libgcc >"$LOGDIR/gcc-stage1-install.log" 2>&1 \
|| print -r -- "!! install had errors (see $LOGDIR/gcc-stage1-install.log)"

# quick smoke
if command -v "$TRIPLE-gcc" >/dev/null 2>&1; then
  log "Smoke test: $TRIPLE-gcc -v"
  "$TRIPLE-gcc" -v || true
else
  print -r -- "!! $TRIPLE-gcc not on PATH; check $PREFIX/bin and logs"
fi

log "Done."
