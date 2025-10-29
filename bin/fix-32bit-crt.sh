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


ts() { print -r -- "[$(date +'%F %T')] $*"; }

# ---- Config ----
: ${PREFIX:="$HOME/opt/mingw"}
: ${TARGET:="x86_64-w64-mingw32"}
: ${BUILD_DIR:="$HOME/build/gcc-mingw-stage1"}

# If you have mingw-w64 sources, set this to the root of the repo (it must contain mingw-w64-crt/)
: ${MINGW_W64_SRC:="$HOME/src/mingw-w64"}

# If you have an existing 32-bit sysroot already (OPTION A), set this to its root, e.g.:
#   export I686_SYSROOT="$HOME/opt/i686-w64-mingw32"
: ${I686_SYSROOT:=""}  # leave empty if you don't have one

# ---- Ensure tool paths/environment ----
export PATH="$PREFIX/$TARGET/bin:$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="/data/data/com.termux/files/usr/lib:$PREFIX/lib:${LD_LIBRARY_PATH:-}"

req=( "$TARGET-objdump" "$TARGET-ar" "$TARGET-ranlib" "$TARGET-ld" )
for t in $req; do
  command -v "$t" >/dev/null || { ts "[FAIL] required tool not found: $t"; exit 1; }
done

# Ensure symlink layout still favors 32-bit for startup objs + import libs
cd "$PREFIX/$TARGET" || { ts "[FAIL] cd $PREFIX/$TARGET"; exit 1; }
mkdir -p lib lib32 lib64

# re-point startup objs to 32-bit
for o in crt2.o dllcrt2.o gcrt2.o; do
  if [ -f "lib/$o" ] && [ ! -L "lib/$o" ]; then mv -f "lib/$o" "lib64/$o"; fi
  if [ -f "lib32/$o" ]; then ln -sf "../lib32/$o" "lib/$o"; fi
done

# re-point import libs to lib32
IMPLIBS=( libmingwthrd.a libmingw32.a libmingwex.a libmoldname.a libmsvcrt.a
          libkernel32.a libuser32.a libshell32.a libadvapi32.a )
for a in $IMPLIBS; do
  if [ -f "lib/$a" ] && [ ! -L "lib/$a" ]; then mv -f "lib/$a" "lib64/$a"; fi
  ln -sf "../lib32/$a" "lib/$a"
done

ts "[*] audit lib32/ import libs (expect pe-i386):"
NEEDS_FIX=0
for a in $IMPLIBS; do
  f="lib32/$a"
  if [ ! -f "$f" ]; then
    ts "  - MISSING: $f"
    NEEDS_FIX=1
    continue
  fi
  # Peek a member inside the archive to detect arch
  member=$("$TARGET-ar" t "$f" 2>/dev/null | head -n 1)
  if [ -z "$member" ]; then
    ts "  - EMPTY or unreadable: $f"
    NEEDS_FIX=1
    continue
  fi
  tmp="$HOME$TMP/.peek.$$.$a.o"
  rm -f "$tmp"; "$TARGET-ar" x "$f" "$member" && mv -f "$member" "$tmp" 2>/dev/null
  if [ ! -f "$tmp" ]; then
    ts "  - could not extract member from $f"
    NEEDS_FIX=1
    continue
  fi
  arch=$("$TARGET-objdump" -f "$tmp" 2>/dev/null | awk '/file format/ {print $NF}')
  rm -f "$tmp"
  ts "  - %-22s -> %s" "$a" "$arch"
  if [ "$arch" != "pe-i386" ]; then
    NEEDS_FIX=1
  fi
done

if [ $NEEDS_FIX -eq 0 ]; then
  ts "[OK] lib32/* are pe-i386 already. You can rebuild now."
else
  ts "[!] lib32/* contain 64-bit or are missing. We must populate true 32-bit import libs."

  # ---------- OPTION A: COPY from an i686 sysroot ----------
  if [ -n "$I686_SYSROOT" ] && [ -d "$I686_SYSROOT/i686-w64-mingw32/lib" ]; then
    ts "[*] Option A: copying from $I686_SYSROOT"
    for a in $IMPLIBS crt2.o dllcrt2.o gcrt2.o; do
      src="$I686_SYSROOT/i686-w64-mingw32/lib/$a"
      if [ -f "$src" ]; then
        cp -f "$src" "lib32/$a"
        "$TARGET-ranlib" "lib32/$a" >/dev/null 2>&1 || true
        ts "  copied $a"
      else
        ts "  missing in source: $src"
      fi
    done
  else
    # ---------- OPTION B: BUILD 32-bit CRT into lib32 ----------
    ts "[*] Option B: building 32-bit mingw-w64 CRT into lib32/"
    if [ ! -d "$MINGW_W64_SRC/mingw-w64-crt" ]; then
      ts "[FAIL] mingw-w64 sources not found at $MINGW_W64_SRC (looking for mingw-w64-crt/)"
      ts "       Set MINGW_W64_SRC to your mingw-w64 repo dir and re-run."
      exit 1
    fi

    CRT_BUILD="$HOME/build/mingw-w64-crt-32"
    rm -rf "$CRT_BUILD"; mkdir -p "$CRT_BUILD"
    cd "$CRT_BUILD" || exit 1

    # We drive a 32-bit CRT build but keep host as x86_64-w64-mingw32 (multilib flavor)
    # Key bits:
    #  - compile with -m32
    #  - install into $PREFIX/$TARGET/lib32
    #  - use the headers from your existing sysroot
    export CC="$TARGET-gcc -m32"
    export AR="$TARGET-ar"
    export RANLIB="$TARGET-ranlib"
    export CFLAGS="-O2 -pipe -m32"
    export LDFLAGS="-m32"

    ts "[*] configuring mingw-w64-crt (32-bit)"
    # We don't run "configure" for mingw-w64-crt; it's a Makefile-driven tree.
    # Use makefile variables to direct headers/sysroot/libdir.
    make -C "$MINGW_W64_SRC/mingw-w64-crt" clean >/dev/null 2>&1 || true

    ts "[*] building 32-bit CRT/import libs"
    make -C "$MINGW_W64_SRC/mingw-w64-crt" \
      PREFIX="$PREFIX/$TARGET" \
      CRTDLL=msvcrt \
      install-libraries-32 install-startfiles-32 \
      DESTDIR="/" \
      CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
      LIB32_DIR="$PREFIX/$TARGET/lib32" || {
        ts "[FAIL] building/installing 32-bit CRT"
        exit 1
      }

    ts "[OK] installed 32-bit CRT/startfiles into $PREFIX/$TARGET/lib32"
  fi

  # Re-audit after copy/build
  ts "[*] re-audit lib32/ import libs:"
  BAD=0
  for a in $IMPLIBS; do
    f="lib32/$a"
    if [ ! -f "$f" ]; then ts "  - STILL missing: $f"; BAD=1; continue; fi
    member=$("$TARGET-ar" t "$f" 2>/dev/null | head -n 1)
    [ -n "$member" ] || { ts "  - BAD archive: $f"; BAD=1; continue; }
    tmp="$HOME$TMP/.peek.$$.$a.o"
    rm -f "$tmp"; "$TARGET-ar" x "$f" "$member" && mv -f "$member" "$tmp" 2>/dev/null
    arch=$("$TARGET-objdump" -f "$tmp" 2>/dev/null | awk '/file format/ {print $NF}')
    rm -f "$tmp"
    ts "  - %-22s -> %s" "$a" "$arch"
    [ "$arch" = "pe-i386" ] || BAD=1
  done
  if [ $BAD -ne 0 ]; then
    ts "[FAIL] lib32 still not pure 32-bit; cannot proceed."
    exit 1
  fi
fi

# ---- If we got here, lib32 looks correct; rebuild libgcc (32-bit multilib) ----
ts "[*] setting build env to prefer 32-bit libs"
export LIBRARY_PATH="$PREFIX/$TARGET/lib32:$PREFIX/$TARGET/lib"
export LDFLAGS_FOR_TARGET="-L$PREFIX/$TARGET/lib32 -L$PREFIX/$TARGET/lib"
export LD_FOR_TARGET="$PREFIX/$TARGET/bin/ld -m i386pe"

cd "$BUILD_DIR" || { ts "[FAIL] cd $BUILD_DIR"; exit 1; }
ts "[*] cleaning stale 32-bit libgcc"
rm -rf x86_64-w64-mingw32/32/libgcc/{shlib,*.o,*.a,*.dll} 2>/dev/null || true

ts "[*] building 32-bit libgcc"
LIBRARY_PATH="$LIBRARY_PATH" \
LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET" \
LD_FOR_TARGET="$LD_FOR_TARGET" \
make -j"$(nproc)" all-target-libgcc || {
  ts "[FAIL] all-target-libgcc failed"; exit 1;
}

ts "[*] installing 32-bit libgcc"
LIBRARY_PATH="$LIBRARY_PATH" \
LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET" \
LD_FOR_TARGET="$LD_FOR_TARGET" \
make install-target-libgcc || {
  ts "[FAIL] install-target-libgcc failed"; exit 1;
}

ts "[OK] 32-bit libgcc built & installed."
