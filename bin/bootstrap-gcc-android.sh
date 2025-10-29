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


ANDROID_API_DEFAULT=28
TARGET_DEFAULT="aarch64-linux-android"
WORKROOT_DEFAULT="$HOME/toolchain-work"
PREFIX_DEFAULT="$HOME/opt/toolchain"
BINUTILS_VER_DEFAULT="2.42"
GCC_VER_DEFAULT="13.2.0"
PARALLEL_DEFAULT="$(nproc 2>/dev/null || echo 4)"
GNU_MIRROR="${GNU_MIRROR:-https://ftp.gnu.org/gnu}"

PREFIX="${PREFIX:-$PREFIX_DEFAULT}"
WORKROOT="${WORKROOT:-$WORKROOT_DEFAULT}"
SRC="${SRC:-$HOME/src}"
BUILD="${BUILD:-$HOME/build}"
LOG_DIR="${LOG_DIR:-$HOME/logs/gcc-bootstrap}"
ANDROID_API="${ANDROID_API:-$ANDROID_API_DEFAULT}"
TARGET="${TARGET:-$TARGET_DEFAULT}"
PARALLEL="${PARALLEL:-$PARALLEL_DEFAULT}"

mkdir -p "$LOG_DIR" "$SRC" "$BUILD" "$WORKROOT"
LOG_FILE="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

step(){ printf "\033[34m[STEP %s]\033[0m %s\n" "$(date +%F\ %T)" "$*"; }
ok(){ printf "\033[32m[OK]\033[0m %s\n" "$*"; }
warn(){ printf "\033[33m[WARN]\033[0m %s\n" "$*"; }
die(){ printf "\033[31m[FATAL]\033[0m %s\n" "$*"; exit 1; }

usage(){
  cat <<U
Usage: $(basename "$0") [--api=N] [--prefix=DIR] [--parallel=N]
Phases: binutils -> gcc(stage1) -> stage sysroot -> gcc(stage2)+libgcc
U
}

# simple parser
while [ $# -gt 0 ]; do
  case "$1" in
    --api=*) ANDROID_API="${1#*=}"; shift;;
    --prefix=*) PREFIX="${1#*=}"; shift;;
    --parallel=*) PARALLEL="${1#*=}"; shift;;
    --help|-h) usage; exit 0;;
    *) warn "unknown arg $1"; shift;;
  esac
done

# Preflight
step "Installing Termux deps"
pkg update -y || true
# note: package names in Termux:
# gmp, mpfr, libmpc, isl, zlib, rsync, build-essential
pkg install -y curl tar xz-utils git build-essential \
  gmp mpfr libmpc isl zlib rsync python cmake ninja pkg-config

[ -d "$PREFIX" ] || mkdir -p "$PREFIX"
ok "Dirs ready: PREFIX=$PREFIX WORKROOT=$WORKROOT"

# Tools: use NDK clang if present; otherwise clang from Termux
if [ -n "${NDK_LLVM_BIN:-}" ] && command -v "$NDK_LLVM_BIN/clang" >/dev/null 2>&1; then
  export CC="$NDK_LLVM_BIN/clang --target=${TARGET}${ANDROID_API} --sysroot=$NDK_SYSROOT"
  export CXX="$NDK_LLVM_BIN/clang++ --target=${TARGET}${ANDROID_API} --sysroot=$NDK_SYSROOT -stdlib=libc++"
  export AR="$NDK_LLVM_BIN/llvm-ar"; export RANLIB="$NDK_LLVM_BIN/llvm-ranlib"; export STRIP="$NDK_LLVM_BIN/llvm-strip"
else
  export CC="clang"; export CXX="clang++"
  export AR="llvm-ar"; export RANLIB="llvm-ranlib"; export STRIP="llvm-strip"
fi

export CFLAGS="-O2 -fPIC"; export CXXFLAGS="-O2 -fPIC"; export LDFLAGS=""
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"; export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"

fetch(){
  local url="$1"; local out="$SRC/$(basename "$url")"
  [ -f "$out" ] || curl -L -o "$out" "$url"
  echo "$out"
}

build_binutils(){
  local ver="${BINUTILS_VER:-$BINUTILS_VER_DEFAULT}"
  local tar; tar="$(fetch "$GNU_MIRROR/binutils/binutils-$ver.tar.xz")"
  step "Unpack binutils-$ver"; rm -rf "$WORKROOT/binutils-$ver"; tar -C "$WORKROOT" -xf "$tar"
  step "Configure binutils ($TARGET)"
  rm -rf "$BUILD/binutils-$ver"; mkdir -p "$BUILD/binutils-$ver"; cd "$BUILD/binutils-$ver"
  "$WORKROOT/binutils-$ver/configure" \
    --target="$TARGET" --prefix="$PREFIX" \
    --with-sysroot="${NDK_SYSROOT:-/}" --disable-nls --disable-werror
  step "Build binutils"; make -j"$PARALLEL"
  step "Install binutils"; make install
  ok "binutils installed"
}

build_gcc_stage1(){
  local ver="${GCC_VER:-$GCC_VER_DEFAULT}"
  local tar; tar="$(fetch "$GNU_MIRROR/gcc/gcc-$ver/gcc-$ver.tar.xz")"
  step "Unpack gcc-$ver"; rm -rf "$WORKROOT/gcc-$ver"; tar -C "$WORKROOT" -xf "$tar"
  step "Configure gcc stage1 (C only, no headers)"
  rm -rf "$BUILD/gcc-$ver-stage1"; mkdir -p "$BUILD/gcc-$ver-stage1"; cd "$BUILD/gcc-$ver-stage1"
  "$WORKROOT/gcc-$ver/configure" \
    --target="$TARGET" --prefix="$PREFIX" \
    ${NDK_SYSROOT:+--with-sysroot="$NDK_SYSROOT"} \
    --disable-nls --enable-languages=c --without-headers --disable-multilib \
    --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libsanitizer --disable-libssp
  step "Build gcc (stage1)"; make all-gcc -j"$PARALLEL"
  step "Install gcc (stage1)"; make install-gcc
}

stage_sysroot(){
  [ -n "${NDK_SYSROOT:-}" ] || { warn "NDK_SYSROOT not set; skipping stage_sysroot copy"; return 0; }
  step "Stage sysroot to $PREFIX/sysroot"
  mkdir -p "$PREFIX/sysroot"
  rsync -a --delete "$NDK_SYSROOT"/ "$PREFIX/sysroot"/
}

build_gcc_stage2(){
  local ver="${GCC_VER:-$GCC_VER_DEFAULT}"
  step "Configure gcc stage2 (C,C++)"
  rm -rf "$BUILD/gcc-$ver-stage2"; mkdir -p "$BUILD/gcc-$ver-stage2"; cd "$BUILD/gcc-$ver-stage2"
  "$WORKROOT/gcc-$ver/configure" \
    --target="$TARGET" --prefix="$PREFIX" \
    --with-sysroot="$PREFIX/sysroot" --disable-nls --enable-languages=c,c++ --disable-multilib
  step "Build gcc (stage2)"; make -j"$PARALLEL"
  step "Install gcc (stage2)"; make install
  step "Build/install target libgcc"; make all-target-libgcc -j"$PARALLEL" && make install-target-libgcc
}

sanity(){
  step "Sanity compile"
  echo 'int main(){return 0;}' > "$BUILD/hello.c"
  "$PREFIX/bin/${TARGET}-gcc" --sysroot="$PREFIX/sysroot" "$BUILD/hello.c" -o "$BUILD/hello"
  file "$BUILD/hello" || true
  ok "sanity OK"
}

echo "==== GCC/Toolchain Bootstrap (API $ANDROID_API, target $TARGET) ===="
build_binutils
build_gcc_stage1
stage_sysroot
build_gcc_stage2
sanity
echo "==== DONE at $PREFIX (log: $LOG_FILE) ===="
