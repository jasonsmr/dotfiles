# Build & run a tiny PIE using your GCC with the aarch64 NDK sysroot.
# No wildcards/globs; uses explicit CRT object paths.

TRIPLE="${TRIPLE:-aarch64-linux-android}"
API="${API:-28}"
NDK_ROOT="${NDK_ROOT:-$HOME/opt/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64}"
NDK_SYSROOT="${NDK_SYSROOT:-$NDK_ROOT/sysroot}"
GCC="${GCC:-$HOME/opt/toolchain/aarch64-linux-android/bin/$TRIPLE-gcc}"

# cc1 runtime deps
export LD_LIBRARY_PATH="$HOME/opt/host-libs/lib:${LD_LIBRARY_PATH-}"

# Find Clang resource dir (on aarch64 hosts it's under lib/clang)
if [ -d "$NDK_ROOT/lib/clang" ]; then
  CLANG_BASE="$NDK_ROOT/lib/clang"
elif [ -d "$NDK_ROOT/lib64/clang" ]; then
  # fallback (shouldn't be needed on aarch64, but harmless)
  CLANG_BASE="$NDK_ROOT/lib64/clang"
else
  echo "!! Couldn't find Clang resource dir under $NDK_ROOT/{lib,lib64}/clang"
  exit 1
fi

# Pick latest clang version dir
CLANG_VER="$(ls -1 "$CLANG_BASE" 2>/dev/null | sort -V | tail -n1)"
RESLIB="$CLANG_BASE/$CLANG_VER/lib/linux/aarch64"

# Expected CRT objects (no globs)
SCRT1="$NDK_SYSROOT/usr/lib/$TRIPLE/$API/Scrt1.o"
CRTI="$NDK_SYSROOT/usr/lib/$TRIPLE/$API/crti.o"
CRTN="$NDK_SYSROOT/usr/lib/$TRIPLE/$API/crtn.o"
CRTBEGIN="$RESLIB/crtbegin_dynamic.o"
CRTEND="$RESLIB/crtend_android.o"

# Verify files exist (print helpful hints instead of crashing)
for f in "$SCRT1" "$CRTI" "$CRTN" "$CRTBEGIN" "$CRTEND"; do
  [ -r "$f" ] || { echo "!! Missing: $f"; echo "   Check NDK path/API=$API and host arch (aarch64)"; exit 1; }
done

# Minimal test program
mkdir -p "$HOME/tmp"
cat > "$HOME/tmp/hello.c" <<'EOF'
#include <stdio.h>
int main(void){ puts("hello"); return 0; }
EOF

# Show include search to confirm we’re pointing at the right sysroot dirs
"$GCC" --sysroot="$NDK_SYSROOT" -D__ANDROID_API__=$API -v -E -xc - </dev/null 2>&1 \
  | sed -n '/search starts here/,/End of search list/p'

# Compile & link explicitly with correct CRTs; PIE + dynamic libc; libgcc static only
"$GCC" --sysroot="$NDK_SYSROOT" -D__ANDROID_API__=$API \
  -fPIE -pie \
  "$HOME/tmp/hello.c" \
  "$SCRT1" "$CRTI" "$CRTBEGIN" \
  -Wl,--sysroot="$NDK_SYSROOT" \
  -Wl,-rpath-link,"$NDK_SYSROOT/usr/lib/$TRIPLE/$API" \
  -L"$NDK_SYSROOT/usr/lib/$TRIPLE/$API" -lc -ldl -lm \
  "$CRTEND" "$CRTN" \
  -static-libgcc \
  -o "$HOME/tmp/hello" || { echo "!! link failed"; exit 1; }

echo "Built: $HOME/tmp/hello"
"$HOME/tmp/hello"
