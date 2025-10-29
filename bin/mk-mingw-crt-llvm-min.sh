#!/usr/bin/env bash
# mk-mingw-crt-llvm-min.sh  —  rebuild only MinGW-w64 headers+CRT/import-libs with LLVM tools
# No 'pipefail', no '-u'. Keeps output readable and avoids terminal aborts on minor issues.

# ---- configuration via env ----
: "${SYS64:?set SYS64 to x86_64 sysroot (…/x86_64-w64-mingw32/x86_64-w64-mingw32)}"
: "${SYS32:?set SYS32 to i686   sysroot (…/i686-w64-mingw32/i686-w64-mingw32)}"
: "${LLVM_SRC:?set LLVM_SRC to your llvm-project root}"

echo "== Using =="
echo "SYS64 = $SYS64"
echo "SYS32 = $SYS32"

# Find Clang resource dir (builtins)
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

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need clang; need llvm-ar; need llvm-ranlib; need make

# ---- get mingw-w64 sources (headers+crt) if MINGW_SRC is not set) ----
if [ -z "$MINGW_SRC" ]; then
  WRK="$HOME/build/mingw-src-min"
  mkdir -p "$WRK"
  if [ ! -d "$WRK/mingw-w64" ]; then
    echo "Fetching mingw-w64 sources (headers+crt)…"
    curl -L https://github.com/mingw-w64/mingw-w64/archive/refs/heads/master.tar.gz -o "$WRK/mingw.tar.gz"
    mkdir -p "$WRK/mingw-w64"
    tar -xzf "$WRK/mingw.tar.gz" -C "$WRK" --strip-components=1
  fi
  MINGW_SRC="$WRK"
fi
echo "MINGW_SRC = $MINGW_SRC"

HDRS="$MINGW_SRC/mingw-w64-headers"
CRT="$MINGW_SRC/mingw-w64-crt"

# ---- install headers into each sysroot/include ----
build_headers () {
  TGT="$1"; SYS="$2"
  BLD="$MINGW_SRC/build-headers-$TGT"
  rm -rf "$BLD"; mkdir -p "$BLD"; cd "$BLD"
  echo "== Headers ($TGT) =="
  "$HDRS/configure" --host="$TGT" --prefix="$SYS" --enable-sdk=all --enable-secure-api
  make -j$(nproc) && make install
}

build_headers x86_64-w64-mingw32 "$SYS64"
build_headers i686-w64-mingw32   "$SYS32"

# ---- build CRT + import libs with clang/llvm-ar/llvm-ranlib ----
build_crt () {
  TGT="$1"; SYS="$2"
  BLD="$MINGW_SRC/build-crt-$TGT"
  rm -rf "$BLD"; mkdir -p "$BLD"; cd "$BLD"
  echo "== CRT ($TGT) =="
  CC="clang --target=$TGT --sysroot=$SYS"
  AR="llvm-ar" RANLIB="llvm-ranlib" \
  "$CRT/configure" --host="$TGT" --prefix="$SYS" --with-sysroot="$SYS"
  make -j$(nproc) AR=llvm-ar RANLIB=llvm-ranlib CC="$CC" && make install
}

build_crt x86_64-w64-mingw32 "$SYS64"
build_crt i686-w64-mingw32   "$SYS32"

# ---- recreate libgcc.a (builtins) and libgcc_eh.a (shim + libunwind) ----
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
long __stdcall _gnu_exception_handler(void* a, void* b, void* c, void* d){
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

# ---- tiny hello tests with canonical MSVCRT link order ----
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

echo "== link test (x64) =="
clang --target=x86_64-w64-mingw32 --sysroot="$SYS64" -fuse-ld=lld -rtlib=compiler-rt \
  "$HOME/t64.c" \
  -Wl,-entry,mainCRTStartup \
  -Wl,--start-group \
    -lmingw32 -lmoldname -lmingwex -lmsvcrt-os -lmsvcrt \
    -ladvapi32 -lshell32 -luser32 -lkernel32 \
    -lgcc_eh -lgcc \
  -Wl,--end-group \
  -o "$HOME/a64.exe" -v

echo "== link test (x86) =="
clang --target=i686-w64-mingw32 --sysroot="$SYS32" -fuse-ld=lld -rtlib=compiler-rt \
  "$HOME/t32.c" \
  -Wl,-entry,mainCRTStartup \
  -Wl,--start-group \
    -lmingw32 -lmoldname -lmingwex -lmsvcrt-os -lmsvcrt \
    -ladvapi32 -lshell32 -luser32 -lkernel32 \
    -lgcc_eh -lgcc \
  -Wl,--end-group \
  -o "$HOME/a32.exe" -v

file "$HOME/a64.exe" || true
file "$HOME/a32.exe" || true
echo "== done =="
