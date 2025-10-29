#!/usr/bin/env bash
# fix-mingw-linker.sh — put libunwind + builtins shims into the *working* MinGW sysroots and test link

set -e

# --- Use the verified, working sysroots ---
SYS64="${SYS64:-$HOME/opt/mingw/x86_64-w64-mingw32}"
SYS32="${SYS32:-$HOME/opt/mingw/i686-w64-mingw32}"
LLVM_SRC="${LLVM_SRC:-$HOME/src/llvm-project}"

echo "== Using =="
echo "SYS64 = $SYS64"
echo "SYS32 = $SYS32"
echo "LLVM  = $LLVM_SRC"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need clang; need llvm-ar; need llvm-ranlib; need cmake; need ninja

# Find Clang resource dir (for compiler-rt builtins)
if [ -z "$RD" ]; then
  for base in "$HOME/opt/android-ndk-r27b" "$HOME/opt/android-sdk/ndk/latest"; do
    d="$base/toolchains/llvm/prebuilt/linux-x86_64/lib/clang"
    [ -d "$d" ] || continue
    v=$(ls "$d" | sort -V | tail -n1)
    if [ -n "$v" ] && [ -d "$d/$v" ]; then RD="$d/$v"; break; fi
  done
fi
[ -n "$RD" ] || { echo "Could not locate Clang resource dir (…/lib/clang/<ver>). Set RD."; exit 1; }
echo "RD    = $RD"

# --- Build libunwind into the *mingw* sysroots ---
build_unwind () {
  TGT="$1"; SYS="$2"; BLD="$HOME/build/libunwind-${TGT}"
  rm -rf "$BLD"
  cmake -S "$LLVM_SRC/libunwind" -B "$BLD" -G Ninja \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_TARGET="$TGT" \
    -DCMAKE_CXX_COMPILER_TARGET="$TGT" \
    -DCMAKE_SYSROOT="$SYS" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DLIBUNWIND_ENABLE_SHARED=OFF \
    -DLIBUNWIND_ENABLE_STATIC=ON \
    -DLIBUNWIND_ENABLE_THREADS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$SYS" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_INCLUDEDIR=include
  ninja -C "$BLD" install
}

echo "== Building libunwind =="
build_unwind x86_64-w64-mingw32 "$SYS64"
build_unwind i686-w64-mingw32   "$SYS32"

# --- Create libgcc.a (builtins) and libgcc_eh.a (gnu_exception_handler shim + libunwind) in the *mingw* sysroots ---
echo "== libgcc builtins shim =="
( cd "$SYS64/lib" && rm -f libgcc.a && llvm-ar qc libgcc.a "$RD/lib/windows/libclang_rt.builtins-x86_64.a" && llvm-ranlib libgcc.a )
( cd "$SYS32/lib" && rm -f libgcc.a && llvm-ar qc libgcc.a "$RD/lib/windows/libclang_rt.builtins-i386.a"    && llvm-ranlib libgcc.a )

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/geh64.c" <<'EOF'
#ifdef __cplusplus
extern "C" {
#endif
__declspec(dllimport) long __C_specific_handler(void*, void*, void*, void*);
long _gnu_exception_handler(void* a, void* b, void* c, void* d){
  return __C_specific_handler(a,b,c,d);
}
#ifdef __cplusplus
}
#endif
EOF
cat > "$TMP/geh32.c" <<'EOF'
#ifdef __cplusplus
extern "C" {
#endif
__declspec(dllimport) long __stdcall __C_specific_handler(void*, void*, void*, void*);
long __stdcall __gnu_exception_handler(void* a, void* b, void* c, void* d){
  return __C_specific_handler(a,b,c,d);
}
#ifdef __cplusplus
}
#endif
EOF

clang --target=x86_64-w64-mingw32 --sysroot="$SYS64" -c "$TMP/geh64.c" -o "$TMP/geh64.o"
clang --target=i686-w64-mingw32   --sysroot="$SYS32" -c "$TMP/geh32.c" -o "$TMP/geh32.o"

echo "== libgcc_eh shim =="
( cd "$SYS64/lib" && rm -f libgcc_eh.a && llvm-ar qc libgcc_eh.a "$TMP/geh64.o" libunwind.a && llvm-ranlib libgcc_eh.a )
( cd "$SYS32/lib" && rm -f libgcc_eh.a && llvm-ar qc libgcc_eh.a "$TMP/geh32.o" libunwind.a && llvm-ranlib libgcc_eh.a )

# --- Minimal hello tests linked against the *mingw* sysroots ---
[ -f "$HOME/t64.c" ] || cat > "$HOME/t64.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ puts("hello x64"); Sleep(10); return 0; }
EOF
[ -f "$HOME/t32.c" ] || cat > "$HOME/t32.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ puts("hello x86"); Sleep(10); return 0; }
EOF

echo "== link test (x64, mingw sysroot) =="
clang --target=x86_64-w64-mingw32 --sysroot="$SYS64" -fuse-ld=lld \
  "$HOME/t64.c" -o "$HOME/a64.exe" \
  -Wl,-entry,mainCRTStartup \
  -Wl,--start-group -lmingw32 -lmoldname -lmingwex -lmsvcrt -Wl,--end-group -v

echo "== link test (x86, mingw sysroot) =="
clang --target=i686-w64-mingw32 --sysroot="$SYS32" -fuse-ld=lld \
  "$HOME/t32.c" -o "$HOME/a32.exe" \
  -Wl,-entry,mainCRTStartup \
  -Wl,--start-group -lmingw32 -lmoldname -lmingwex -lmsvcrt -Wl,--end-group -v

file "$HOME/a64.exe" || true
file "$HOME/a32.exe" || true
echo "== done =="
