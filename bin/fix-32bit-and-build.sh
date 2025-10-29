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

# Requires a working x86_64-w64-mingw32 toolchain under $PREFIX/bin.

# ---- config (reuse your env if already exported) ----
PREFIX="${PREFIX:-$HOME/opt/mingw}"
TARGET="${TARGET:-x86_64-w64-mingw32}"            # existing cross toolchain
BUILD_DIR="${BUILD_DIR:-$HOME/build/gcc-mingw-stage1}"
MINGW_W64_SRC="${MINGW_W64_SRC:-$HOME/src/mingw-w64}"
STAGE="${STAGE:-$HOME$TMP/i686-stage}"            # i686 sysroot

# ---- helpers ----
ts() { date +"[%Y-%m-%d %H:%M:%S]"; }
log() { echo "$(ts) $*"; }

# Always bypass weird aliases/functions (like ln alias in zsh/p10k)
safe_ln() {
  if command ln -sf "$1" "$2" 2>/dev/null; then
    return 0
  fi
  # Fallback: copy when hardlink/symlink not possible
  command cp -a "$1" "$2"
}

# Ensure dirs exist
mkdir -p "$PREFIX/bin" "$PREFIX/$TARGET/bin" "$BUILD_DIR" "$STAGE" "$STAGE/i686-w64-mingw32"

log "[*] env:
    PREFIX=$PREFIX
    TARGET=$TARGET
    BUILD_DIR=$BUILD_DIR
    MINGW_W64_SRC=$MINGW_W64_SRC
    STAGE=$STAGE"

# ---- sanity: require x86_64-w64-mingw32 toolchain ----
REAL_GCC="$PREFIX/bin/$TARGET-gcc"
REAL_GPP="$PREFIX/bin/$TARGET-g++"
REAL_AS="$PREFIX/bin/$TARGET-as"
REAL_AR="$PREFIX/bin/$TARGET-ar"
REAL_RANLIB="$PREFIX/bin/$TARGET-ranlib"
REAL_DLLTOOL="$PREFIX/bin/$TARGET-dlltool"
REAL_WINDRES="$PREFIX/bin/$TARGET-windres"
REAL_STRIP="$PREFIX/bin/$TARGET-strip"

for t in "$REAL_GCC" "$REAL_GPP" "$REAL_AR" "$REAL_RANLIB" "$REAL_DLLTOOL" "$REAL_WINDRES"; do
  if [[ ! -x "$t" ]]; then
    log "[FAIL] missing $t; ensure your $TARGET toolchain is installed under $PREFIX/bin"
    exit 1
  fi
done

# Detect clang backend (only then use -target)
is_clang() { "$1" -v 2>&1 | grep -qi 'clang'; }
IS_CLANG_CC=0;  is_clang "$REAL_GCC" && IS_CLANG_CC=1
IS_CLANG_CXX=0; is_clang "$REAL_GPP" && IS_CLANG_CXX=1

log "[*] creating i686-w64-mingw32 wrapper toolchain (if missing)"

WRAP_DIR="$PREFIX/bin"
TRIP_DIR="$PREFIX/$TARGET/bin"
mkdir -p "$WRAP_DIR" "$TRIP_DIR"

# atomic writer
write_wrap() {
  local path="$1"; shift
  local body="$*"
  local tmp="${path}.tmp.$$"
  printf "%s\n" "$body" > "$tmp"
  chmod +x "$tmp"
  mv -f "$tmp" "$path"
}

# i686 gcc wrapper
I686_GCC="$WRAP_DIR/i686-w64-mingw32-gcc"
if [[ $IS_CLANG_CC -eq 1 ]]; then
  write_wrap "$I686_GCC" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$REAL_GCC\" -m32 --sysroot=\"$STAGE\" -target i686-w64-mingw32 \"\$@\""
else
  write_wrap "$I686_GCC" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$REAL_GCC\" -m32 --sysroot=\"$STAGE\" \"\$@\""
fi

# i686 g++ wrapper
I686_GPP="$WRAP_DIR/i686-w64-mingw32-g++"
if [[ $IS_CLANG_CXX -eq 1 ]]; then
  write_wrap "$I686_GPP" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$REAL_GPP\" -m32 --sysroot=\"$STAGE\" -target i686-w64-mingw32 \"\$@\""
else
  write_wrap "$I686_GPP" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$REAL_GPP\" -m32 --sysroot=\"$STAGE\" \"\$@\""
fi

# as wrapper (prefer --32 if available)
I686_AS="$WRAP_DIR/i686-w64-mingw32-as"
if [[ -x "$REAL_AS" ]]; then
  write_wrap "$I686_AS" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$REAL_AS\" --32 \"\$@\""
else
  # rare fallback: use gcc -c as assembler frontend
  write_wrap "$I686_AS" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$REAL_GCC\" -m32 --sysroot=\"$STAGE\" -c \"\$@\""
fi

# trivial forwards (ar, ranlib, dlltool, strip)
for n in ar ranlib dlltool strip; do
  real_var="REAL_$(echo "$n" | tr '[:lower:]' '[:upper:]')"
  real="${!real_var}"
  write_wrap "$WRAP_DIR/i686-w64-mingw32-$n" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$real\" \"\$@\""
done

# windres needs 32-bit COFF target
I686_WINDRES="$WRAP_DIR/i686-w64-mingw32-windres"
write_wrap "$I686_WINDRES" "#!/data/data/com.termux/files/usr/bin/bash
exec \"$REAL_WINDRES\" --target=pe-i386 \"\$@\""

# Triplet-bin convenience links
for w in i686-w64-mingw32-{gcc,g++,as,ar,ranlib,dlltool,windres,strip}; do
  [[ -e "$TRIP_DIR/$w" ]] || safe_ln "../../bin/$w" "$TRIP_DIR/$w"
done

# Put our wrappers first on PATH
export PATH="$WRAP_DIR:$TRIP_DIR:$PATH"

# ---- headers: install once into sysroot if missing ----
if [[ ! -d "$STAGE/i686-w64-mingw32/include" ]]; then
  log "[*] installing 32-bit headers to stage sysroot"
  mkdir -p "$BUILD_DIR/mw64-headers-32"
  cd "$BUILD_DIR/mw64-headers-32" || exit 1
  if [[ -f Makefile && -f config.status ]]; then
    make distclean >/dev/null 2>&1 || true
  fi
  "$MINGW_W64_SRC/mingw-w64-headers/configure" \
    --host=i686-w64-mingw32 \
    --prefix="$STAGE/i686-w64-mingw32" || { log "[FAIL] configure headers"; exit 1; }
  make -j"$(nproc 2>/dev/null || echo 2)" || { log "[FAIL] make headers"; exit 1; }
  make install || { log "[FAIL] install headers"; exit 1; }
else
  log "[*] headers already present in $STAGE"
fi

# ---- CRT build (32-bit) ----
log "[*] configuring 32-bit CRT"
mkdir -p "$BUILD_DIR/mw64-crt-32"
cd "$BUILD_DIR/mw64-crt-32" || exit 1

log "    [toolcheck] CC -> $(command -v i686-w64-mingw32-gcc)"

CFG_LOG="$BUILD_DIR/mw64-crt-32/crt-configure.log"

# Clean a half-done configure to avoid 'already configured'
if [[ -f Makefile && -f config.status ]]; then
  make distclean >/dev/null 2>&1 || true
fi

"$MINGW_W64_SRC/mingw-w64-crt/configure" \
  --host=i686-w64-mingw32 \
  --with-sysroot="$STAGE" \
  --prefix="$STAGE/i686-w64-mingw32" \
  CC="i686-w64-mingw32-gcc" \
  CXX="i686-w64-mingw32-g++" \
  AR="i686-w64-mingw32-ar" \
  RANLIB="i686-w64-mingw32-ranlib" \
  DLLTOOL="i686-w64-mingw32-dlltool" \
  WINDRES="i686-w64-mingw32-windres" \
  >"$CFG_LOG" 2>&1

if [[ $? -ne 0 ]]; then
  log "[configure FAIL] See: $CFG_LOG"
  tail -n 60 "$CFG_LOG" 2>/dev/null || true
  exit 1
fi

log "[*] building 32-bit CRT"
make -j"$(nproc 2>/dev/null || echo 2)" || { log "[FAIL] make CRT"; exit 1; }
make install || { log "[FAIL] install CRT"; exit 1; }

log "[OK] 32-bit CRT installed under $STAGE/i686-w64-mingw32"
