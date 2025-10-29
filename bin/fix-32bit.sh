#!/data/data/com.termux/files/usr/bin/env zsh
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


# Disable history expansion so "!" in strings doesn't explode
set +H
# Don’t error on unmatched globs in zsh
setopt null_glob

###############################################################################
# Config (tweak if needed)
###############################################################################
export PREFIX="${PREFIX:-$HOME/opt/mingw}"
export TARGET="${TARGET:-x86_64-w64-mingw32}"
export BUILD_DIR="${BUILD_DIR:-$HOME/build/gcc-mingw-stage1}"
export TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr$HOME$TMP}"

# Prefer 32-bit libs for target links and force ld to 32-bit PE for -m32
export LIBRARY_PATH="$PREFIX/$TARGET/lib32:$PREFIX/$TARGET/lib"
export LDFLAGS_FOR_TARGET="-L$PREFIX/$TARGET/lib32 -L$PREFIX/$TARGET/lib"
export LD_FOR_TARGET="$PREFIX/$TARGET/bin/ld -m i386pe"

ts() { print -r -- "[$(date +%F' '%T)] $*"; }
need() { command -v "$1" >/dev/null 2>&1 }
run() {
  local desc="$1"; shift
  ts "[*] $desc"
  "$@"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    ts "[FAIL] ($rc): $*"
    return $rc
  fi
  return 0
}
warn() { ts "[warn] $*"; }

###############################################################################
# Tool checks
###############################################################################
ts "[*] checking tools..."
for t in "$TARGET-gcc" "$TARGET-objdump" "$TARGET-nm" ranlib make; do
  if ! need "$t"; then
    ts "[FAIL] missing required tool: $t"
    exit 1
  fi
done

###############################################################################
# Paths
###############################################################################
TROOT="$PREFIX/$TARGET"
LIB32="$TROOT/lib32"
LIB64="$TROOT/lib64"
LIBDEF="$TROOT/lib"

ts "[*] environment:"
ts "    PREFIX=$PREFIX"
ts "    TARGET=$TARGET"
ts "    BUILD_DIR=$BUILD_DIR"
ts "    TMPDIR=$TMPDIR"
ts "    LIBRARY_PATH=$LIBRARY_PATH"
ts "    LDFLAGS_FOR_TARGET=$LDFLAGS_FOR_TARGET"
ts "    LD_FOR_TARGET=$LD_FOR_TARGET"

[[ -d "$TROOT" ]]  || { ts "[FAIL] target root not found: $TROOT"; exit 1; }
[[ -d "$LIB32"  ]] || { ts "[FAIL] 32-bit lib dir not found: $LIB32"; exit 1; }
[[ -d "$LIBDEF" ]] || { ts "[FAIL] lib dir not found: $LIBDEF"; exit 1; }

###############################################################################
# Arrange import libs: move real 64-bit libs into lib64; symlink 32-bit into lib
###############################################################################
ts "[*] arranging import libs (move 64-bit -> lib64, symlink 32-bit -> lib)..."
mkdir -p "$LIB64"

IMPORTS=(
  libmingwthrd.a
  libmingw32.a
  libmingwex.a
  libmoldname.a
  libmsvcrt.a
  libkernel32.a
  libuser32.a
  libshell32.a
  libadvapi32.a
)

# Move any real files sitting in lib/ (keep existing symlinks)
for a in $IMPORTS; do
  if [[ -e "$LIBDEF/$a" && ! -L "$LIBDEF/$a" ]]; then
    ts "    moving: $LIBDEF/$a -> $LIB64/$a"
    mv -f "$LIBDEF/$a" "$LIB64/$a" || { ts "[FAIL] move failed for $a"; exit 1; }
  fi
done

# Symlink lib/ -> lib32/
for a in $IMPORTS; do
  if [[ -e "$LIB32/$a" ]]; then
    ln -sfn "../lib32/$a" "$LIBDEF/$a"
    ts "    symlinked: $LIBDEF/$a -> ../lib32/$a"
  else
    warn "$LIB32/$a missing; leaving $LIBDEF/$a as-is (if any)"
  fi
done

###############################################################################
# Re-index 32-bit archives
###############################################################################
ts "[*] reindexing 32-bit archives with ranlib ..."
if (( ${#${(f)"$(ls "$LIB32"/*.a 2>/dev/null)"}[@]} )); then
  if need "$TARGET-ranlib"; then
    for a in "$LIB32"/*.a; do "$TARGET-ranlib" "$a" || warn "ranlib failed on $a"; done
  else
    for a in "$LIB32"/*.a; do ranlib "$a" || warn "ranlib failed on $a"; done
  fi
else
  warn "no *.a archives found in $LIB32"
fi

###############################################################################
# Probe for __head_lib32_* (non-fatal; info only)
###############################################################################
ts "[*] probing for __head_lib32_* symbols ..."
for a in libkernel32.a libmsvcrt.a; do
  if [[ -e "$LIB32/$a" ]]; then
    count=$("$TARGET-nm" -g --defined-only "$LIB32/$a" 2>/dev/null | grep -ci '__head_lib32_' || true)
    ts "    $a: ${count} matches for '__head_lib32_'"
  else
    warn "skip probe; missing $LIB32/$a"
  fi
done

###############################################################################
# Build/install only target libgcc
###############################################################################
if [[ ! -d "$BUILD_DIR" ]]; then
  ts "[FAIL] build dir not found: $BUILD_DIR"
  exit 1
fi

ts "[*] building target libgcc (preferring 32-bit libs)..."
cd "$BUILD_DIR" || { ts "[FAIL] cd failed: $BUILD_DIR"; exit 1; }

# Clean stale 32-bit libgcc outputs if dir exists
if [[ -d "$BUILD_DIR/$TARGET/32/libgcc" ]]; then
  ts "    cleaning stale outputs in $BUILD_DIR/$TARGET/32/libgcc"
  rm -rf "$BUILD_DIR/$TARGET/32/libgcc/shlib" \
         "$BUILD_DIR/$TARGET/32/libgcc/"*.o \
         "$BUILD_DIR/$TARGET/32/libgcc/"*.a \
         "$BUILD_DIR/$TARGET/32/libgcc/"*.dll 2>/dev/null || true
fi

run "make all-target-libgcc" \
  env LIBRARY_PATH="$LIBRARY_PATH" \
      LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET" \
      LD_FOR_TARGET="$LD_FOR_TARGET" \
      make -j"$(nproc)" all-target-libgcc \
  || exit $?

run "make install-target-libgcc" \
  env LIBRARY_PATH="$LIBRARY_PATH" \
      LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET" \
      LD_FOR_TARGET="$LD_FOR_TARGET" \
      make install-target-libgcc \
  || exit $?

###############################################################################
# Quick 32-bit link sanity test (non-fatal)
###############################################################################
ts "[*] quick 32-bit link sanity test ..."
mkdir -p "$TMPDIR"
TEST_C="$TMPDIR/zt.c"
TEST_O="$TMPDIR/zt.o"
TEST_EXE="$TMPDIR/zt32.exe"

cat > "$TEST_C" <<'EOF'
int main(void){return 0;}
EOF

"$TARGET-gcc" -m32 -c "$TEST_C" -o "$TEST_O" 2>&1 | sed 's/^/    /'
"$TARGET-gcc" -m32 -nostdlib -Wl,-e,mainCRTStartup \
  "$LIB32/crt2.o" "$TEST_O" \
  -Wl,--start-group \
    -L"$LIB32" \
    -lmingw32 -lmingwex -lmoldname -lmsvcrt -lkernel32 -luser32 -lshell32 -ladvapi32 \
  -Wl,--end-group \
  -o "$TEST_EXE" 2>&1 | sed 's/^/    /' || warn "test link failed (non-fatal)"

if [[ -e "$TEST_EXE" ]]; then
  ts "    objdump format (expect pe/pei-i386):"
  "$TARGET-objdump" -f "$TEST_EXE" | head -n 10 | sed 's/^/    /'
fi

ts "[*] all done."
ts "If libgcc still fails with '__head_lib32_*' refs:"
ts "  - ensure $LIB32/*.a exist and were reindexed;"
ts "  - confirm -L$LIB32 appears before -L$TROOT/lib in link lines;"
ts "  - last resort: export:"
ts "      LDFLAGS_FOR_TARGET='-Wl,--whole-archive -L$LIB32 -lmingwthrd -lmingw32 -lmingwex -lmoldname -lmsvcrt -ladvapi32 -lshell32 -luser32 -lkernel32 -Wl,--no-whole-archive'"
ts "    and rerun: make -j\$(nproc) all-target-libgcc && make install-target-libgcc"
