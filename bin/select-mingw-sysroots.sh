#!/data/data/com.termux/files/usr/bin/bash
# select-mingw-sysroots.sh — set SYS64/SYS32 to the *MinGW* sysroots (not toolchain),
# then do a quick symbol check and a tiny link test.

set -e

MIN64="$HOME/opt/mingw/x86_64-w64-mingw32"
MIN32="$HOME/opt/mingw/i686-w64-mingw32"

# Hard fail if these aren’t real MinGW roots
for D in "$MIN64" "$MIN32"; do
  test -d "$D/include" && test -d "$D/lib" || {
    echo "[ERR] Not a valid MinGW sysroot: $D"; exit 1;
  }
done

export SYS64="$MIN64"
export SYS32="$MIN32"

echo "== Using MinGW sysroots =="
echo "SYS64 = $SYS64"
echo "SYS32 = $SYS32"

# Quick symbol probes that must exist in MinGW CRT/import libs
echo "== Probing required symbols =="
for pair in \
  "libmingw32.a:_pei386_runtime_relocator" \
  "libmsvcrt.a:_initterm" \
  "libmsvcrt.a:__p__fmode" \
  "libmsvcrt.a:__p__commode" \
  "libmingwex.a:__mingw_setusermatherr"
do
  lib="${pair%%:*}"; sym="${pair##*:}"
  if ! llvm-nm -g --defined-only "$SYS64/lib/$lib" | grep -q "$sym"; then
    echo "[WARN] x64 missing $sym in $lib"; fi
  if ! llvm-nm -g --defined-only "$SYS32/lib/$lib" | grep -q "$sym"; then
    echo "[WARN] x86 missing $sym in $lib"; fi
done

# Tiny hello test with canonical MSVCRT order (no -nostdlib gymnastics)
cat > "$HOME/t64.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ puts("hello x64"); Sleep(10); return 0; }
EOF
cat > "$HOME/t32.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ puts("hello x86"); Sleep(10); return 0; }
EOF

echo "== Link test (x64) with MinGW sysroot =="
clang --target=x86_64-w64-mingw32 --sysroot="$SYS64" -fuse-ld=lld -rtlib=compiler-rt \
  "$HOME/t64.c" -Wl,-entry,mainCRTStartup \
  -Wl,--start-group -lmingw32 -lmingwex -lmoldname -lmsvcrt -Wl,--end-group \
  -ladvapi32 -lshell32 -luser32 -lkernel32 \
  -o "$HOME/a64.exe" -v

echo "== Link test (x86) with MinGW sysroot =="
clang --target=i686-w64-mingw32 --sysroot="$SYS32" -fuse-ld=lld -rtlib=compiler-rt \
  "$HOME/t32.c" -Wl,-entry,mainCRTStartup \
  -Wl,--start-group -lmingw32 -lmingwex -lmoldname -lmsvcrt -Wl,--end-group \
  -ladvapi32 -lshell32 -luser32 -lkernel32 \
  -o "$HOME/a32.exe" -v

file "$HOME/a64.exe" || true
file "$HOME/a32.exe" || true
echo "== done =="
