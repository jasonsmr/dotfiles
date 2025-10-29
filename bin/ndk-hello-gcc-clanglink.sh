#!/usr/bin/env sh
# Compile with your GCC, link with NDK clang (which supplies CRTs).
# No set -e; no wildcards; robust on Termux.

TRIPLE="${TRIPLE:-aarch64-linux-android}"
API="${API:-28}"
NDK_ROOT="${NDK_ROOT:-$HOME/opt/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64}"
NDK_SYSROOT="${NDK_SYSROOT:-$NDK_ROOT/sysroot}"
GCC="${GCC:-$HOME/opt/toolchain/aarch64-linux-android/bin/$TRIPLE-gcc}"

# Host libs for cc1
export LD_LIBRARY_PATH="$HOME/opt/host-libs/lib:${LD_LIBRARY_PATH-}"

# Avoid include pollution
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH ANDROID_NDK_HOME ANDROID_NDK_ROOT

# Find GCC's builtin include directory (for stddef.h etc)
GCCLIB="$("$GCC" -print-libgcc-file-name 2>/dev/null)"
GCCINC=""
if [ -n "$GCCLIB" ]; then
  GDIR="$(dirname "$GCCLIB")"                  # .../lib/gcc/<triple>/<ver>
  GCCINC="$GDIR/include"                       # builtin headers
fi

# Find NDK clang for link step
CLANG_BIN=""
for b in "$NDK_ROOT/bin/${TRIPLE}${API}-clang" "$NDK_ROOT/bin/${TRIPLE}-clang"; do
  [ -x "$b" ] && { CLANG_BIN="$b"; break; }
done

if [ -z "$CLANG_BIN" ]; then
  echo "!! Could not find NDK clang in $NDK_ROOT/bin"
  exit 1
fi

# Override file for GCC (tight, safe, and portable)
OVR="$HOME/tmp/ndk_gcc_ovr.txt"
mkdir -p "$HOME/tmp"
cat >"$OVR" <<EOF
-nostdinc
--sysroot=$NDK_SYSROOT
-isystem $GCCINC
-isystem $NDK_SYSROOT/usr/include
-isystem $NDK_SYSROOT/usr/include/$TRIPLE
-D__ANDROID_API__=$API
# neutralize a few clang-only annotations/macros used by Bionic headers
-D__INTRODUCED_IN(x)=
-D__INTRODUCED_IN_64(x)=
-D__INTRODUCED_IN_ARM(x)=
-D__INTRODUCED_IN_X86(x)=
-D__INTRODUCED_IN_MIPS(x)=
-D__DEPRECATED_IN(x,y,z)=
-D__REMOVED_IN(x)=
-D_Nonnull=
-D_Nullable=
-D_Null_unspecified=
-D__has_feature(x)=0
-D__attribute_pure__=
EOF

# Tiny test program
cat > "$HOME/tmp/hello.c" <<'EOF'
#include <stdio.h>
int main(void){ puts("hello"); return 0; }
EOF

echo "== compile with GCC =="
"$GCC" @"$OVR" -fPIE -c "$HOME/tmp/hello.c" -o "$HOME/tmp/hello.o" || {
  echo "!! GCC compile failed"; exit 1;
}

echo "== link with NDK clang (supplying CRTs) =="
"$CLANG_BIN" --sysroot="$NDK_SYSROOT" -D__ANDROID_API__=$API \
  -fPIE -pie "$HOME/tmp/hello.o" -o "$HOME/tmp/hello" \
  -Wl,-rpath-link,"$NDK_SYSROOT/usr/lib/$TRIPLE/$API" -lc -ldl -lm || {
    echo "!! clang link failed"; exit 1;
  }

echo "Built: $HOME/tmp/hello"
"$HOME/tmp/hello"
