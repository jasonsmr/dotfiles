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


PREFIX_DIR="${1:-$HOME/opt/box64}"
SRC_TOP="$HOME/build/box64"
SRC_DIR="$SRC_TOP/box64"
BUILD_DIR="$SRC_DIR/build"
mkdir -p "$PREFIX_DIR" "$BUILD_DIR"

need=(clang cmake ninja python pkg-config git)
for b in "${need[@]}"; do command -v "$b" >/dev/null || { echo "missing: $b (pkg install $b)"; exit 1; }; end

[ -d "$SRC_DIR" ] || { echo "[box64] cloning sources"; mkdir -p "$SRC_TOP"; git clone https://github.com/ptitSeb/box64.git "$SRC_DIR"; }
cd "$BUILD_DIR"
rm -f CMakeCache.txt && rm -rf CMakeFiles

cmake -G Ninja .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR" \
  -DCMAKE_C_COMPILER="$NDK_LLVM_BIN/$NDK_TRIPLE-clang" \
  -DCMAKE_CXX_COMPILER="$NDK_LLVM_BIN/$NDK_TRIPLE-clang++" \
  -DARM_DYNAREC=ON -DLD80BITS=OFF -DSTATIC_LINKING=OFF -DHAVE_VULKAN=ON \
  -DCMAKE_C_FLAGS="--sysroot=$NDK_SYSROOT -D__ANDROID_API__=$ANDROID_API" \
  -DCMAKE_CXX_FLAGS="--sysroot=$NDK_SYSROOT -D__ANDROID_API__=$ANDROID_API -stdlib=libc++ -isystem $NDK_SYSROOT/usr/include/c++/v1" \
  -DCMAKE_EXE_LINKER_FLAGS="--sysroot=$NDK_SYSROOT" \
  -DCMAKE_SHARED_LINKER_FLAGS="--sysroot=$NDK_SYSROOT"

ninja -v
ninja install
echo "[box64] Installed to $PREFIX_DIR"
echo "Tips:"
echo "  export BOX64_DYNAREC=1"
echo "  export BOX64_VULKAN=1"
