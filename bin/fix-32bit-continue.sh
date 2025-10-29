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

# No 'set -e' here on purpose; we keep going and print clear status.
set -u

ts() { print -r -- "[$(date '+%F %T')] $*"; }

# --- Defaults (respect existing env if you already exported them) ---
: "${PREFIX:=$HOME/opt/mingw}"
: "${TARGET:=x86_64-w64-mingw32}"
: "${BUILD_DIR:=$HOME/build/gcc-mingw-stage1}"
: "${TMPDIR:=${HOME}$HOME$TMP}"

# Termux base lib dir (where libzstd.so.* lives after install)
TERMUX_LIB="/data/data/com.termux/files/usr/lib"

# Cross tool dir
XT="$PREFIX/$TARGET"
XBIN="$XT/bin"

ts "[*] environment:"
ts "    PREFIX=$PREFIX"
ts "    TARGET=$TARGET"
ts "    BUILD_DIR=$BUILD_DIR"
ts "    TMPDIR=$TMPDIR"

# --- Make sure required binaries exist ---
need_bins=(
  "$XBIN/$TARGET-ranlib"
  "$XBIN/$TARGET-ar"
  "$XBIN/$TARGET-ld"
)
missing=0
for b in $need_bins; do
  if [[ ! -x "$b" ]]; then
    ts "[FAIL] required tool not found: $b"
    missing=1
  fi
done
if (( missing )); then
  ts "[hint] Build/install your cross binutils & gcc stage bits first so $XBIN has the $TARGET-* tools."
  exit 1
fi

# --- Ensure libzstd is available (Termux) ---
if [[ ! -e "$TERMUX_LIB/libzstd.so" && ! -e "$TERMUX_LIB/libzstd.so.1" ]]; then
  ts "[*] libzstd not found in $TERMUX_LIB — attempting: pkg install -y zstd"
  if command -v pkg >/dev/null 2>&1; then
    yes | pkg install -y zstd >/dev/null 2>&1
  elif command -v apt >/dev/null 2>&1; then
    yes | apt install -y zstd >/dev/null 2>&1
  fi
fi
if [[ ! -e "$TERMUX_LIB/libzstd.so" && ! -e "$TERMUX_LIB/libzstd.so.1" ]]; then
  ts "[WARN] libzstd still not found. You can install it manually (Termux: pkg install zstd)."
else
  ts "[*] libzstd present."
fi

# Build a safe LD_LIBRARY_PATH that includes Termux libs and any hostdeps you may have
HOSTDEPS_LIB="$PREFIX/hostdeps/lib"
export LD_LIBRARY_PATH="$TERMUX_LIB"
[[ -d "$HOSTDEPS_LIB" ]] && export LD_LIBRARY_PATH="$HOSTDEPS_LIB:$LD_LIBRARY_PATH"

# Also keep your earlier LIBRARY_PATH (linker search for archives), if you had it
: "${LIBRARY_PATH:=$XT/lib32:$XT/lib}"
export LIBRARY_PATH

# Keep your earlier LDFLAGS_FOR_TARGET ordering (32-bit before 64-bit)
: "${LDFLAGS_FOR_TARGET:=-L$XT/lib32 -L$XT/lib}"
export LDFLAGS_FOR_TARGET

# Force binutils to 32-bit PE emulation for multilib link steps
export LD_FOR_TARGET="$XBIN/$TARGET-ld -m i386pe"

ts "[*] LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
ts "[*] LIBRARY_PATH=$LIBRARY_PATH"
ts "[*] LDFLAGS_FOR_TARGET=$LDFLAGS_FOR_TARGET"
ts "[*] LD_FOR_TARGET=$LD_FOR_TARGET"

# --- Re-index 32-bit import libs with ranlib (some builds require it) ---
ts "[*] ranlib-ing 32-bit archives under $XT/lib32 ..."
count_ok=0
count_fail=0
for a in "$XT"/lib32/*.a(.N); do
  "$XBIN/$TARGET-ranlib" "$a" >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    ((count_ok++))
  else
    ((count_fail++))
    # Show a few failures, but don't spam endlessly
    if (( count_fail <= 20 )); then
      ts "[warn] ranlib failed on ${a:t}"
    fi
  fi
done
ts "[*] ranlib summary: ok=$count_ok fail=$count_fail"

# --- Try building the 32-bit libgcc multilib again ---
if [[ -d "$BUILD_DIR" ]]; then
  ts "[*] kicking libgcc 32-bit build in $BUILD_DIR ..."
  cd "$BUILD_DIR" || { ts "[FAIL] cd $BUILD_DIR"; exit 1; }

  # Optional: clean stale 32-bit libgcc outputs
  if [[ -d x86_64-w64-mingw32/32/libgcc ]]; then
    ts "[*] cleaning stale 32-bit libgcc outputs ..."
    rm -rf x86_64-w64-mingw32/32/libgcc/shlib x86_64-w64-mingw32/32/libgcc/*.o \
           x86_64-w64-mingw32/32/libgcc/*.a x86_64-w64-mingw32/32/libgcc/*.dll 2>/dev/null
  fi

  ts "[*] make all-target-libgcc (this can take a while)..."
  make -j"$(nproc)" all-target-libgcc
  mk_ec=$?

  if (( mk_ec != 0 )); then
    ts "[FAIL] all-target-libgcc returned $mk_ec"
    ts "[hint] If the error mentions missing '__head_lib32_*' or '__chkstk_ms', it still isn't picking"
    ts "       32-bit import libs first. Confirm the symlinks in:"
    ts "         $XT/lib  -> pointing to ../lib32/*.a"
    ts "       and that 'ld -m i386pe' is being used (LD_FOR_TARGET above)."
    exit $mk_ec
  fi

  ts "[*] make install-target-libgcc ..."
  make install-target-libgcc
  inst_ec=$?
  if (( inst_ec != 0 )); then
    ts "[FAIL] install-target-libgcc returned $inst_ec"
    exit $inst_ec
  fi

  ts "[OK] 32-bit libgcc multilib build+install completed."
else
  ts "[FAIL] BUILD_DIR not found: $BUILD_DIR"
  exit 1
fi

# --- Sanity test: link a trivial 32-bit exe using the arranged libs ---
ts "[*] quick sanity link test (32-bit) ..."
mkdir -p "$TMPDIR"
cat > "$TMPDIR/t.c" <<'EOF'
int main(void){return 0;}
EOF

"$XBIN/$TARGET-gcc" -m32 -c "$TMPDIR/t.c" -o "$TMPDIR/t.o"
"$XBIN/$TARGET-gcc" -m32 -nostdlib -Wl,-e,mainCRTStartup \
  "$XT/lib32/crt2.o" "$TMPDIR/t.o" \
  -Wl,--start-group \
  -L"$XT/lib32" -lmingw32 -lmingwex -lmoldname -lmsvcrt -lkernel32 -luser32 -lshell32 -ladvapi32 \
  -Wl,--end-group \
  -o "$TMPDIR/t32.exe"
link_ec=$?

if (( link_ec == 0 )); then
  ts "[OK] sanity link produced $TMPDIR/t32.exe"
else
  ts "[WARN] sanity link failed ($link_ec)."
  ts "       Check that $XT/lib has symlinks to ../lib32/*.a and that they exist."
  ts "       Also inspect: $XT/lib32/libmsvcrt.a and friends for '__head_lib32_*' symbols with:"
  ts "         $XBIN/$TARGET-nm -A $XT/lib32/libmsvcrt.a | head"
fi

ts "[DONE]"
