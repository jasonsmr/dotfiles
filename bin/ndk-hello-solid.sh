#!/usr/bin/env sh
# Robust hello for Android/aarch64 using your GCC + NDK.
# - Finds CRT objects automatically
# - Shims a few Clang-isms so GCC can parse Bionic headers
# - Falls back to NDK clang for *linking only* if startfiles are missing

TRIPLE="${TRIPLE:-aarch64-linux-android}"
API="${API:-28}"
NDK_ROOT="${NDK_ROOT:-$HOME/opt/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64}"
NDK_SYSROOT="${NDK_SYSROOT:-$NDK_ROOT/sysroot}"
GCC="${GCC:-$HOME/opt/toolchain/aarch64-linux-android/bin/$TRIPLE-gcc}"

# cc1 runtime deps
export LD_LIBRARY_PATH="$HOME/opt/host-libs/lib:${LD_LIBRARY_PATH-}"

# Prevent include pollution
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH ANDROID_NDK_HOME ANDROID_NDK_ROOT

# Prefer aarch64 resource dir (crtbegin/crtend live here)
if [ -d "$NDK_ROOT/lib/clang" ]; then
  CLANG_BASE="$NDK_ROOT/lib/clang"
elif [ -d "$NDK_ROOT/lib64/clang" ]; then
  CLANG_BASE="$NDK_ROOT/lib64/clang"
else
  CLANG_BASE=""
fi
[ -n "$CLANG_BASE" ] && CLANG_VER="$(ls -1 "$CLANG_BASE" 2>/dev/null | sort -V | tail -n1)"
[ -n "$CLANG_VER" ] && RESLIB="$CLANG_BASE/$CLANG_VER/lib/linux/aarch64"

# helper: pick first existing path, or empty
pick_first() {
  chosen=""
  for p in "$@"; do [ -r "$p" ] && { chosen="$p"; break; }; done
  printf '%s' "$chosen"
}

# Try common locations; if not found, search the tree (quietly)
find_crt() {
  name="$1"
  shift
  cand="$(pick_first "$@")"
  if [ -n "$cand" ]; then printf '%s' "$cand"; return 0; fi
  # search under NDK_ROOT then NDK_SYSROOT
  found="$(find "$NDK_ROOT" -type f -name "$name" 2>/dev/null | head -n1)"
  [ -z "$found" ] && found="$(find "$NDK_SYSROOT" -type f -name "$name" 2>/dev/null | head -n1)"
  printf '%s' "$found"
}

# Locate startfiles
SCRT1="$(find_crt Scrt1.o \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API/Scrt1.o" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/Scrt1.o" \
  "$NDK_ROOT/$TRIPLE/lib/$API/Scrt1.o")"

CRTI="$(find_crt crti.o \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API/crti.o" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/crti.o" \
  "$NDK_ROOT/$TRIPLE/lib/$API/crti.o")"

CRTN="$(find_crt crtn.o \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API/crtn.o" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/crtn.o" \
  "$NDK_ROOT/$TRIPLE/lib/$API/crtn.o")"

CRTBEGIN="$(find_crt crtbegin_dynamic.o \
  "${RESLIB:-}/crtbegin_dynamic.o")"

CRTEND="$(find_crt crtend_android.o \
  "${RESLIB:-}/crtend_android.o")"

# Find a libdir with libc.so for this API
LIBDIR=""
for d in \
  "$NDK_SYSROOT/usr/lib/$TRIPLE/$API" \
  "$NDK_SYSROOT/usr/lib/$TRIPLE" \
  "$NDK_ROOT/$TRIPLE/lib/$API" \
  "$NDK_ROOT/$TRIPLE/lib"; do
  [ -r "$d/libc.so" ] && { LIBDIR="$d"; break; }
done
[ -z "$LIBDIR" ] && LIBDIR="$(dirname "$(find "$NDK_SYSROOT" -type f -name libc.so 2>/dev/null | head -n1)")"

echo "== using =="
echo "GCC      : $GCC"
echo "SYSROOT  : $NDK_SYSROOT"
[ -n "$RESLIB" ] && echo "RESLIB   : $RESLIB"
echo "LIBDIR   : $LIBDIR"
echo "SCRT1    : ${SCRT1:-<missing>}"
echo "CRTI     : ${CRTI:-<missing>}"
echo "CRTBEGIN : ${CRTBEGIN:-<missing>}"
echo "CRTEND   : ${CRTEND:-<missing>}"
echo "CRTN     : ${CRTN:-<missing>}"

mkdir -p "$HOME/tmp"

cat > "$HOME/tmp/hello.c" <<'EOF'
#include <stdio.h>
int main(void){ puts("hello"); return 0; }
EOF

# Minimal shim for Clang-isms that bother GCC when reading Bionic headers
OVR="$HOME/tmp/ndk_gcc_ovr.txt"
cat > "$OVR" <<EOF
--sysroot=$NDK_SYSROOT
-isystem $NDK_SYSROOT/usr/include
-isystem $NDK_SYSROOT/usr/include/$TRIPLE
-D__ANDROID_API__=$API
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

# Show include search (for sanity)
"$GCC" @"$OVR" -v -E -xc - </dev/null 2>&1 \
  | sed -n '/search starts here/,/End of search list/p'

# Compile with GCC
"$GCC" @"$OVR" -fPIE -c "$HOME/tmp/hello.c" -o "$HOME/tmp/hello.o" || {
  echo "!! GCC compile failed"; exit 1;
}

# Link with GCC if we have all CRT pieces; otherwise try NDK clang for link step only
need_clang_link=0
for f in "$SCRT1" "$CRTI" "$CRTBEGIN" "$CRTEND" "$CRTN" "$LIBDIR/libc.so"; do
  [ -r "$f" ] || { need_clang_link=1; break; }
done

if [ "$need_clang_link" -eq 0 ]; then
  "$GCC" @"$OVR" -fPIE -pie \
    "$HOME/tmp/hello.o" \
    "$SCRT1" "$CRTI" "$CRTBEGIN" \
    -Wl,--sysroot="$NDK_SYSROOT" \
    -Wl,-rpath-link,"$LIBDIR" \
    -L"$LIBDIR" -lc -ldl -lm \
    "$CRTEND" "$CRTN" \
    -static-libgcc \
    -o "$HOME/tmp/hello" || { echo "!! GCC link failed"; exit 1; }
else
  # Find NDK clang and use it only for the final link
  CLANG_BIN=""
  for b in \
    "$NDK_ROOT/bin/${TRIPLE}${API}-clang" \
    "$NDK_ROOT/bin/${TRIPLE}-clang"; do
    [ -x "$b" ] && { CLANG_BIN="$b"; break; }
  done
  if [ -z "$CLANG_BIN" ]; then
    echo "!! Startfiles missing and no NDK clang found to link."
    echo "   Try: find \"$NDK_ROOT\" -name 'Scrt1.o' -o -name 'crtbegin_dynamic.o'"
    exit 1
  fi
  echo "!! Linking with $CLANG_BIN (compile was GCC)"
  "$CLANG_BIN" --sysroot="$NDK_SYSROOT" -D__ANDROID_API__=$API \
    -fPIE -pie "$HOME/tmp/hello.o" -o "$HOME/tmp/hello" \
    -Wl,-rpath-link,"$LIBDIR" -L"$LIBDIR" -lc -ldl -lm || {
      echo "!! clang link failed"; exit 1;
    }
fi

echo "Built: $HOME/tmp/hello"
"$HOME/tmp/hello"
