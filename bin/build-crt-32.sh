#!/data/data/com.termux/files/usr/bin/zsh
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


set -u

ts(){ print -r -- "[$(date +'%F %T')] $*"; }

# --- Config (can be overridden via env) ---
: ${PREFIX:="$HOME/opt/mingw"}
: ${TARGET:="x86_64-w64-mingw32"}
: ${BUILD_DIR:="$HOME/build/gcc-mingw-stage1"}
: ${MINGW_W64_SRC:="$HOME/src/mingw-w64"}     # must contain mingw-w64-crt/
: ${WRAP_TRIPLET:="i686-w64-mingw32"}        # 32-bit host triplet

export PATH="$PREFIX/$TARGET/bin:$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="/data/data/com.termux/files/usr/lib:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

# --- Required tools check ---
need_tools=( "$TARGET-gcc" "$TARGET-g++" "$TARGET-ar" "$TARGET-ranlib" "$TARGET-ld" "$TARGET-objdump" )
for t in "${need_tools[@]}"; do
  command -v "$t" >/dev/null || { ts "[FAIL] missing $t on PATH"; exit 1; }
done
[ -d "$MINGW_W64_SRC/mingw-w64-crt" ] || { ts "[FAIL] mingw-w64-crt not found at $MINGW_W64_SRC/mingw-w64-crt"; exit 1; }

# --- Create i686 wrapper toolchain (force -m32 / i386pe) ---
WRAP_DIR="$PREFIX/bin"
mkdir -p "$WRAP_DIR"
mkwrap(){
  local name body path
  name="$1"
  body="$2"
  path="$WRAP_DIR/$name"
  printf '%s\n' "#!/data/data/com.termux/files/usr/bin/bash
$body" > "$path"
  chmod +x "$path"
  ts "[*] wrapper created: $path"
}

ts "[*] creating wrapper toolchain for $WRAP_TRIPLET"
mkwrap "$WRAP_TRIPLET-gcc"     "$TARGET-gcc -m32 \"\$@\""
mkwrap "$WRAP_TRIPLET-g++"     "$TARGET-g++ -m32 \"\$@\""
mkwrap "$WRAP_TRIPLET-ar"      "$TARGET-ar \"\$@\""
mkwrap "$WRAP_TRIPLET-ranlib"  "$TARGET-ranlib \"\$@\""
mkwrap "$WRAP_TRIPLET-nm"      "$TARGET-nm \"\$@\""
mkwrap "$WRAP_TRIPLET-objdump" "$TARGET-objdump \"\$@\""
mkwrap "$WRAP_TRIPLET-ld"      "$TARGET-ld -m i386pe \"\$@\""
mkwrap "$WRAP_TRIPLET-strip"   "$TARGET-strip \"\$@\""
mkwrap "$WRAP_TRIPLET-objcopy" "$TARGET-objcopy \"\$@\""
mkwrap "$WRAP_TRIPLET-windres" "if command -v $TARGET-windres >/dev/null; then exec $TARGET-windres -F pe-i386 \"\$@\"; else echo 'no windres'; exit 127; fi"

# --- Install dirs ---
I686_SYSROOT="$PREFIX/$WRAP_TRIPLET"
I686_PREFIX="$I686_SYSROOT"
mkdir -p "$I686_PREFIX" "$PREFIX/$TARGET/lib32" "$PREFIX/$TARGET/lib64" "$PREFIX/$TARGET/lib"

# --- Configure & build CRT (32-bit) ---
CRT_BUILD="$HOME/build/mingw-w64-crt-32"
rm -rf "$CRT_BUILD"; mkdir -p "$CRT_BUILD"
cd "$CRT_BUILD" || { ts "[FAIL] cd $CRT_BUILD"; exit 1; }

ts "[*] configuring mingw-w64-crt for host=$WRAP_TRIPLET (32-bit)"
"$MINGW_W64_SRC/mingw-w64-crt/configure" \
  --host="$WRAP_TRIPLET" \
  --prefix="$I686_PREFIX" \
  --with-default-msvcrt=msvcrt \
  CC="$WRAP_TRIPLET-gcc" \
  AR="$WRAP_TRIPLET-ar" \
  RANLIB="$WRAP_TRIPLET-ranlib" \
  NM="$WRAP_TRIPLET-nm" \
  LD="$WRAP_TRIPLET-ld" \
  CFLAGS="-O2 -pipe -m32" \
  LDFLAGS="-m32" || { ts "[FAIL] configure crt"; exit 1; }

ts "[*] building (make -j$(nproc)) mingw-w64-crt (32-bit)"
make -j"$(nproc)" || { ts "[FAIL] make crt"; exit 1; }

ts "[*] installing mingw-w64-crt (32-bit) into $I686_PREFIX"
make install || { ts "[FAIL] make install crt"; exit 1; }

# --- Copy 32-bit import libs & start objects into lib32/, wire lib/ -> lib32/ ---
cd "$PREFIX/$TARGET" || { ts "[FAIL] cd $PREFIX/$TARGET"; exit 1; }

typeset -a IMPLIBS
IMPLIBS=( libmingwthrd.a libmingw32.a libmingwex.a libmoldname.a libmsvcrt.a
          libkernel32.a libuser32.a libshell32.a libadvapi32.a )
typeset -a START_OBJS
START_OBJS=( crt2.o dllcrt2.o gcrt2.o )

ts "[*] copying 32-bit import libs & start files from $I686_PREFIX/lib -> lib32/"
for a in "${IMPLIBS[@]}"; do
  if [ -f "$I686_PREFIX/lib/$a" ]; then
    cp -f "$I686_PREFIX/lib/$a" "lib32/$a"
    "$TARGET-ranlib" "lib32/$a" >/dev/null 2>&1 || true
  fi
done
for o in "${START_OBJS[@]}"; do
  [ -f "$I686_PREFIX/lib/$o" ] && cp -f "$I686_PREFIX/lib/$o" "lib32/$o"
done

# Point lib/ names at 32-bit (move any real 64-bit into lib64/)
for a in "${IMPLIBS[@]}"; do
  if [ -f "lib/$a" ] && [ ! -L "lib/$a" ]; then mv -f "lib/$a" "lib64/$a"; fi
  ln -sf "../lib32/$a" "lib/$a"
done
for o in "${START_OBJS[@]}"; do
  if [ -f "lib/$o" ] && [ ! -L "lib/$o" ]; then mv -f "lib/$o" "lib64/$o"; fi
  [ -f "lib32/$o" ] && ln -sf "../lib32/$o" "lib/$o"
done

# --- Audit lib32 contents (expect pe-i386) ---
ts "[*] auditing lib32/ (expect pe-i386)"
BAD=0
for a in "${IMPLIBS[@]}"; do
  f="lib32/$a"
  if [ ! -f "$f" ]; then ts "  - MISSING $f"; BAD=1; continue; fi
  m=$("$TARGET-ar" t "$f" 2>/dev/null | head -n 1)
  if [ -z "$m" ]; then ts "  - EMPTY $f"; BAD=1; continue; fi
  tmp="$HOME$TMP/.peek.$$.$a.o"; rm -f "$tmp"
  "$TARGET-ar" x "$f" "$m" && mv -f "$m" "$tmp" 2>/dev/null
  arch=$("$TARGET-objdump" -f "$tmp" 2>/dev/null | awk '/file format/ {print $NF}')
  rm -f "$tmp"
  printf '[%s]   - %-22s -> %s\n' "$(date +'%F %T')" "$a" "$arch"
  [ "$arch" = "pe-i386" ] || BAD=1
done
for o in "${START_OBJS[@]}"; do
  f="lib32/$o"
  if [ -f "$f" ]; then
    arch=$("$TARGET-objdump" -f "$f" 2>/dev/null | awk '/file format/ {print $NF}')
    printf '[%s]   - %-22s -> %s\n' "$(date +'%F %T')" "$o" "$arch"
    [ "$arch" = "pe-i386" ] || BAD=1
  fi
done

if [ $BAD -ne 0 ]; then
  ts "[FAIL] lib32 contains non-i386 or missing pieces; cannot continue."
  exit 1
fi

# --- Build env so 32-bit wins ---
export LIBRARY_PATH="$PREFIX/$TARGET/lib32:$PREFIX/$TARGET/lib"
export LDFLAGS_FOR_TARGET="-L$PREFIX/$TARGET/lib32 -L$PREFIX/$TARGET/lib"
export LD_FOR_TARGET="$PREFIX/$TARGET/bin/ld -m i386pe"

# --- Rebuild/install only target libgcc (32-bit multilib) ---
cd "$BUILD_DIR" || { ts "[FAIL] cd $BUILD_DIR"; exit 1; }
ts "[*] cleaning stale 32-bit libgcc artifacts"
rm -rf x86_64-w64-mingw32/32/libgcc/{shlib,*.o,*.a,*.dll} 2>/dev/null || true

ts "[*] building 32-bit libgcc (all-target-libgcc)"
LIBRARY_PATH="$LIBRARY_PATH" \
LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET" \
LD_FOR_TARGET="$LD_FOR_TARGET" \
make -j"$(nproc)" all-target-libgcc || { ts "[FAIL] all-target-libgcc failed"; exit 1; }

ts "[*] installing 32-bit libgcc"
LIBRARY_PATH="$LIBRARY_PATH" \
LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET" \
LD_FOR_TARGET="$LD_FOR_TARGET" \
make install-target-libgcc || { ts "[FAIL] install-target-libgcc failed"; exit 1; }

ts "[OK] 32-bit CRT installed and libgcc (32-bit) built & installed successfully."
