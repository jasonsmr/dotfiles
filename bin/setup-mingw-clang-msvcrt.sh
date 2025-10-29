#!/usr/bin/env bash
# Setup MinGW-w64 + Clang (compiler-rt) on Termux for MSVCRT linking
# - Builds libunwind (static) for x64/x86 into your sysroots
# - Creates libgcc.a shims from compiler-rt builtins
# - Rebuilds libgcc_eh.a to provide _gnu_exception_handler and bundle libunwind
# - Compiles hello-world test EXEs for both x64 and x86 with proper CRT ordering
#
# Required env vars:
#   LLVM_SRC  : path to llvm-project root (contains libunwind/)
#   SYS64     : x86_64-w64-mingw32 sysroot directory
#   SYS32     : i686-w64-mingw32   sysroot directory
#
# Optional (auto-detected if not set):
#   RD        : .../toolchains/llvm/prebuilt/linux-*/lib/clang/<ver>
#
# Tools expected on PATH: clang, clang++, llvm-ar, llvm-ranlib, cmake, ninja, llvm-rc (optional)

set -euo pipefail

# ---------- config & checks ----------
: "${LLVM_SRC:?Set LLVM_SRC to your llvm-project root (contains libunwind)}"
: "${SYS64:?Set SYS64 to your x86_64-w64-mingw32 sysroot}"
: "${SYS32:?Set SYS32 to your i686-w64-mingw32 sysroot}"

# Try to auto-detect RD if not provided
if [[ -z "${RD:-}" ]]; then
  # Common NDK layout under Termux
  for base in "$HOME/opt/android-ndk-r27b" "$HOME/opt/android-sdk/ndk/latest" "$HOME/opt/android-ndk-r27" ; do
    cand="$base/toolchains/llvm/prebuilt/linux-x86_64/lib/clang"
    if [[ -d "$cand" ]]; then
      ver=$(ls "$cand" | sort -V | tail -n1 || true)
      if [[ -n "$ver" && -d "$cand/$ver" ]]; then
        RD="$cand/$ver"
        break
      fi
    fi
  done
fi
: "${RD:?Could not determine RD (…/lib/clang/<ver>). Set RD manually.}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1" >&2; exit 1; }; }
for t in clang clang++ llvm-ar llvm-ranlib cmake ninja; do need "$t"; done
RC_COMPILER="$(command -v llvm-rc || echo rc)"

echo "== Using =="
echo "LLVM_SRC = $LLVM_SRC"
echo "SYS64    = $SYS64"
echo "SYS32    = $SYS32"
echo "RD       = $RD"
echo

mkdir -p "$HOME/build/libunwind-x64" "$HOME/build/libunwind-x86"

# ---------- build & install libunwind (x64) ----------
echo "== Building libunwind (x64) =="
BLD="$HOME/build/libunwind-x64"
rm -rf "$BLD"
cmake -S "$LLVM_SRC/libunwind" -B "$BLD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_COMPILER_TARGET=x86_64-w64-mingw32 \
  -DCMAKE_CXX_COMPILER_TARGET=x86_64-w64-mingw32 \
  -DCMAKE_SYSROOT="$SYS64" \
  -DCMAKE_AR="$(command -v llvm-ar)" \
  -DCMAKE_RANLIB="$(command -v llvm-ranlib)" \
  -DCMAKE_RC_COMPILER="$RC_COMPILER" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBUNWIND_ENABLE_STATIC=ON \
  -DLIBUNWIND_ENABLE_THREADS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SYS64" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_INCLUDEDIR=include \
  -DCMAKE_C_FLAGS="--sysroot=$SYS64 -fms-extensions -fdeclspec" \
  -DCMAKE_CXX_FLAGS="--sysroot=$SYS64 -fms-extensions -fdeclspec"
ninja -C "$BLD" install

# ---------- build & install libunwind (x86) ----------
echo "== Building libunwind (x86) =="
BLD="$HOME/build/libunwind-x86"
rm -rf "$BLD"
cmake -S "$LLVM_SRC/libunwind" -B "$BLD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_COMPILER_TARGET=i686-w64-mingw32 \
  -DCMAKE_CXX_COMPILER_TARGET=i686-w64-mingw32 \
  -DCMAKE_SYSROOT="$SYS32" \
  -DCMAKE_AR="$(command -v llvm-ar)" \
  -DCMAKE_RANLIB="$(command -v llvm-ranlib)" \
  -DCMAKE_RC_COMPILER="$RC_COMPILER" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBUNWIND_ENABLE_STATIC=ON \
  -DLIBUNWIND_ENABLE_THREADS=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$SYS32" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_INCLUDEDIR=include \
  -DCMAKE_C_FLAGS="--sysroot=$SYS32 -fms-extensions -fdeclspec" \
  -DCMAKE_CXX_FLAGS="--sysroot=$SYS32 -fms-extensions -fdeclspec"
ninja -C "$BLD" install

# ---------- create libgcc.a shims from compiler-rt builtins ----------
echo "== Creating libgcc.a (builtins) shims =="

pushd "$SYS64/lib" >/dev/null
  rm -f libgcc.a
  llvm-ar qc libgcc.a "$RD/lib/windows/libclang_rt.builtins-x86_64.a"
  llvm-ranlib libgcc.a
popd >/dev/null

pushd "$SYS32/lib" >/dev/null
  rm -f libgcc.a
  llvm-ar qc libgcc.a "$RD/lib/windows/libclang_rt.builtins-i386.a"
  llvm-ranlib libgcc.a
popd >/dev/null

# ---------- provide _gnu_exception_handler via libgcc_eh.a (and bundle libunwind) ----------
echo "== Rebuilding libgcc_eh.a with _gnu_exception_handler shim + libunwind =="

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cat > "$workdir/gnu_exception_handler_x64.c" <<'EOF'
#ifdef __cplusplus
extern "C" {
#endif
__declspec(dllimport) long __C_specific_handler(void*, void*, void*, void*);
long _gnu_exception_handler(void* rec, void* frame, void* ctx, void* dispatch) {
    return __C_specific_handler(rec, frame, ctx, dispatch);
}
#ifdef __cplusplus
}
#endif
EOF

cat > "$workdir/gnu_exception_handler_x86.c" <<'EOF'
#ifdef __cplusplus
extern "C" {
#endif
__declspec(dllimport) long __stdcall __C_specific_handler(void*, void*, void*, void*);
long __stdcall _gnu_exception_handler(void* rec, void* frame, void* ctx, void* dispatch) {
    return __C_specific_handler(rec, frame, ctx, dispatch);
}
#ifdef __cplusplus
}
#endif
EOF

# build shims
clang --target=x86_64-w64-mingw32 --sysroot="$SYS64" -c \
  "$workdir/gnu_exception_handler_x64.c" -o "$workdir/geh64.o"

clang --target=i686-w64-mingw32 --sysroot="$SYS32" -c \
  "$workdir/gnu_exception_handler_x86.c" -o "$workdir/geh32.o"

# pack libgcc_eh.a
pushd "$SYS64/lib" >/dev/null
  rm -f libgcc_eh.a
  llvm-ar qc libgcc_eh.a "$workdir/geh64.o" libunwind.a
  llvm-ranlib libgcc_eh.a
popd >/dev/null

pushd "$SYS32/lib" >/dev/null
  rm -f libgcc_eh.a
  llvm-ar qc libgcc_eh.a "$workdir/geh32.o" libunwind.a
  llvm-ranlib libgcc_eh.a
popd >/dev/null

# ---------- sanity: symbol checks ----------
echo "== Sanity checks =="
set +e
echo "-- x64 libmsvcrt-os essentials --"
llvm-nm -g --defined-only "$SYS64/lib/libmsvcrt-os.a" | grep -E '__set_app_type|__p__fmode|__p__commode|_setargv|_amsg_exit|_initterm|_pei386_runtime_relocator' || true
echo "-- x64 kernel32 Sleep --"
llvm-nm -g --defined-only "$SYS64/lib/libkernel32.a" | grep -E '\bSleep$' || true
echo "-- x64 _gnu_exception_handler in libgcc_eh.a --"
llvm-nm -g --defined-only "$SYS64/lib/libgcc_eh.a" | grep -E '_gnu_exception_handler$' || true

echo "-- x86 libmsvcrt-os essentials --"
llvm-nm -g --defined-only "$SYS32/lib/libmsvcrt-os.a" | grep -E '___set_app_type|___p__fmode|___p__commode|__setargv|__amsg_exit|__initterm|__pei386_runtime_relocator' || true
echo "-- x86 kernel32 Sleep --"
llvm-nm -g --defined-only "$SYS32/lib/libkernel32.a" | grep -E '_Sleep@4$' || true
echo "-- x86 _gnu_exception_handler in libgcc_eh.a --"
llvm-nm -g --defined-only "$SYS32/lib/libgcc_eh.a" | grep -E '_gnu_exception_handler(@0|@16)$' || true
set -e

# ---------- tiny test sources ----------
[[ -f "$HOME/t64.c" ]] || cat > "$HOME/t64.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ printf("hello x64\n"); Sleep(10); return 0; }
EOF

[[ -f "$HOME/t32.c" ]] || cat > "$HOME/t32.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ printf("hello x86\n"); Sleep(10); return 0; }
EOF

# ---------- link tests (MSVCRT) ----------
echo "== Linking test (x64, MSVCRT) =="
clang --target=x86_64-w64-mingw32 --sysroot="$SYS64" \
  -fuse-ld=lld -rtlib=compiler-rt \
  -Wl,-entry,mainCRTStartup \
  "$SYS64/lib/crt2.o" "$SYS64/lib/crtbegin.o" \
  "$HOME/t64.c" \
  -Wl,--start-group \
    -lmingw32 -lmoldname -lmingwex \
    -lmsvcrt-os -lmsvcrt \
    -ladvapi32 -lshell32 -luser32 -lkernel32 \
    -lgcc_eh -lgcc \
  -Wl,--end-group \
  "$RD/lib/windows/libclang_rt.builtins-x86_64.a" \
  "$SYS64/lib/crtend.o" \
  -o "$HOME/a64.exe" -v

echo "== Linking test (x86, MSVCRT) =="
clang --target=i686-w64-mingw32 --sysroot="$SYS32" \
  -fuse-ld=lld -rtlib=compiler-rt \
  -Wl,-entry,mainCRTStartup \
  "$SYS32/lib/crt2.o" "$SYS32/lib/crtbegin.o" \
  "$HOME/t32.c" \
  -Wl,--start-group \
    -lmingw32 -lmoldname -lmingwex \
    -lmsvcrt-os -lmsvcrt \
    -ladvapi32 -lshell32 -luser32 -lkernel32 \
    -lgcc_eh -lgcc \
  -Wl,--end-group \
  "$RD/lib/windows/libclang_rt.builtins-i386.a" \
  "$SYS32/lib/crtend.o" \
  -o "$HOME/a32.exe" -v

echo
echo "== Done =="
file "$HOME/a64.exe" || true
file "$HOME/a32.exe" || true
