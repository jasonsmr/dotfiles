#!/usr/bin/env sh
# Build & run a tiny PIE with your GCC + Android NDK, auto-finding startfiles.
# Safe for Termux zsh: no set -e, no pipefail, no globs.

TRIPLE="${TRIPLE:-aarch64-linux-android}"
API="${API:-28}"
NDK_ROOT="${NDK_ROOT:-$HOME/opt/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64}"
NDK_SYSROOT="${NDK_SYSROOT:-$NDK_ROOT/sysroot}"
GCC="${GCC:-$HOME/opt/toolchain/aarch64-linux-android/bin/$TRIPLE-gcc}"

# cc1 deps
export LD_LIBRARY_PATH="$HOME/opt/host-libs/lib:${LD_LIBRARY_PATH-}"

# Kill include pollution
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH ANDROID_NDK_HOME ANDROID_NDK_ROOT

# Find Clang resource dir (aarch64 hosts => lib/clang)
if [ -d "$NDK_ROOT/lib/clang" ]; then
  CLANG_BASE="$NDK_ROOT/lib/clang"
elif [ -d "$NDK_ROOT/lib64/clang" ]; then
  CLANG_BASE="$NDK_ROOT/lib64/clang"
else
  echo "!! Couldn't find Clang resource base under $NDK_ROOT/{lib,lib64}/clang"
  exit 1
fi

# Latest clang version dir
CLANG_VER="$(ls -1 "$CLANG_BASE" 2>/dev/null | sort -V | tail -n1)"
[ -n "$CLANG_VER" ] || { echo "!! No clang versions under $CLANG_BASE"; exit 1; }
RESLIB="$CLANG_BASE/$CLANG_VER/lib/linux/aarch64"

# Helper: first readable path among candidates
pick_first() {
  # usage: pick_first VAR_NAME path1 path2 ...
  var="$1"; shift
  chosen=""
  for p in "$@"; do
    if [ -r "$p" ]; then chosen="$p"; break; fi
  done
  if [ -z "$chosen" ]; then
    echo "!! Missing $var. Tried:"
    for p in "$@"; do echo "   - $p"; done
    return 1
  fi
  eval "$var=\"$chosen\""
  return 0
}

# Candidates for startfiles (different NDKs put them in slightly different places)
pick_first SCRT1 \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API/Scrt1.o" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/Scrt1.o" \
  "$NDK_ROOT/$TRIPLE/lib/$API/Scrt1.o"

pick_first CRTI \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API/crti.o" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/crti.o" \
  "$NDK_ROOT/$TRIPLE/lib/$API/crti.o"

pick_first CRTN \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API/crtn.o" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/crtn.o" \
  "$NDK_ROOT/$TRIPLE/lib/$API/crtn.o"

# Clang resource CRTs (should exist here)
pick_first CRTBEGIN "$RESLIB/crtbegin_dynamic.o"
pick_first CRTEND   "$RESLIB/crtend_android.o"

# One of these lib dirs should contain libc.so et al for API=$API
pick_first LIBDIR \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE"

echo "NDK_SYSROOT=$NDK_SYSROOT"
echo "CLANG_RES=$RESLIB"
echo "Startfiles:"
echo "  SCRT1=$SCRT1"
echo "  CRTI =$CRTI"
echo "  CRTBEGIN=$CRTBEGIN"
echo "  CRTEND  =$CRTEND"
echo "  CRTN =$CRTN"
echo "LIBDIR=$LIBDIR"
echo "GCC=$GCC"

# Tiny program
mkdir -p "$HOME/tmp"
cat > "$HOME/tmp/hello.c" <<'EOF'
#include <stdio.h>
int main(void){ puts("hello"); return 0; }
EOF

# Show include search (sanity)
"$GCC" --sysroot="$NDK_SYSROOT" -D__ANDROID_API__=$API -v -E -xc - </dev/null 2>&1 \
  | sed -n '/search starts here/,/End of search list/p'

# Build & link explicitly
"$GCC" --sysroot="$NDK_SYSROOT" -D__ANDROID_API__=$API \
  -fPIE -pie \
  "$HOME/tmp/hello.c" \
  "$SCRT1" "$CRTI" "$CRTBEGIN" \
  -Wl,--sysroot="$NDK_SYSROOT" \
  -Wl,-rpath-link,"$LIBDIR" \
  -L"$LIBDIR" -lc -ldl -lm \
  "$CRTEND" "$CRTN" \
  -static-libgcc \
  -o "$HOME/tmp/hello" || { echo "!! link failed"; exit 1; }

echo "Built: $HOME/tmp/hello"
"$HOME/tmp/hello"
