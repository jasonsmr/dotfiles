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


# ---------- Environment (always repopulate) ----------
export TERMUX_PREFIX="/data/data/com.termux/files/usr"
export HOME_PREFIX="/data/data/com.termux/files/home"

export MINGW_PREFIX="$HOME_PREFIX/opt/mingw"
export TARGET="x86_64-w64-mingw32"

export BUILD_DIR="$HOME_PREFIX/build/gcc-mingw-stage1"
export LOGDIR="$BUILD_DIR/_logs"
export TS="$(date +%Y%m%d-%H%M%S)"

export LIBDIR="$MINGW_PREFIX/$TARGET/lib"          # may NOT exist (ok)
export LIB32DIR="$MINGW_PREFIX/$TARGET/lib32"      # must exist for 32-bit
export LIBGCC_BUILD_DIR="$BUILD_DIR/$TARGET/32/libgcc"

# keep toolchain sane
export PATH="$MINGW_PREFIX/$TARGET/bin:$TERMUX_PREFIX/bin:$PATH"

mkdir -p "$LOGDIR"
log="$LOGDIR/$TS.libgcc32-link-v12.log"
exec > >(tee -a "$log") 2>&1

echo "[INFO] TERMUX_PREFIX=$TERMUX_PREFIX"
echo "[INFO] MINGW_PREFIX=$MINGW_PREFIX"
echo "[INFO] TARGET=$TARGET"
echo "[INFO] BUILD_DIR=$BUILD_DIR"
echo "[INFO] LIBDIR=$LIBDIR (may be absent)"
echo "[INFO] LIB32DIR=$LIB32DIR"
echo "[INFO] LIBGCC_BUILD_DIR=$LIBGCC_BUILD_DIR"
echo "[INFO] LOG=$log"

# ---------- Sanity checks ----------
need() { command -v "$1" >/dev/null 2>&1 || { echo "[ERR] Missing tool: $1"; exit 1; }; }
need "$BUILD_DIR/./gcc/xgcc"
need "$MINGW_PREFIX/$TARGET/bin/ar"
need "$MINGW_PREFIX/$TARGET/bin/ranlib"
command -v "$MINGW_PREFIX/$TARGET/bin/nm" >/dev/null 2>&1 || true

if [[ ! -d "$LIB32DIR" ]]; then
  echo "[ERR] Directory missing: $LIB32DIR"
  exit 1
fi
if [[ ! -d "$LIBGCC_BUILD_DIR" ]]; then
  echo "[ERR] Directory missing: $LIBGCC_BUILD_DIR"
  exit 1
fi

# ---------- Temporarily hide x64/system libs if they exist ----------
HIDE_X64=""
if [[ -d "$LIBDIR" ]]; then
  HIDE_X64="$LIBDIR.x64HIDE.$TS"
  echo "[INFO] Hiding $LIBDIR -> $HIDE_X64"
  mv "$LIBDIR" "$HIDE_X64"
fi

HIDE_MINGW=""
if [[ -d "$MINGW_PREFIX/mingw/lib" ]]; then
  HIDE_MINGW="$MINGW_PREFIX/mingw/lib.HIDE.$TS"
  echo "[INFO] Hiding $MINGW_PREFIX/mingw/lib -> $HIDE_MINGW"
  mv "$MINGW_PREFIX/mingw/lib" "$HIDE_MINGW"
fi

restore() {
  set +e
  if [[ -n "$HIDE_X64" && -d "$HIDE_X64" && ! -d "$LIBDIR" ]]; then
    echo "[INFO] Restoring $LIBDIR"
    mv "$HIDE_X64" "$LIBDIR"
  fi
  if [[ -n "$HIDE_MINGW" && -d "$HIDE_MINGW" && ! -d "$MINGW_PREFIX/mingw/lib" ]]; then
    echo "[INFO] Restoring $MINGW_PREFIX/mingw/lib"
    mv "$HIDE_MINGW" "$MINGW_PREFIX/mingw/lib"
  fi
}
trap restore EXIT

# ---------- Build libgcc.a + objects (no shared yet) ----------
echo "[INFO] Cleaning old objects in $LIBGCC_BUILD_DIR…"
( cd "$LIBGCC_BUILD_DIR" && make clean || true )

echo "[INFO] Building libgcc.a and 32-bit objects (no shared link yet)…"
( cd "$LIBGCC_BUILD_DIR" \
  && make libgcc.a CC="$BUILD_DIR/./gcc/xgcc" CFLAGS="-m32 -O2" ) || {
  echo "[ERR] libgcc.a build failed."
  exit 2
}

# Optional: verify __chkstk_ms symbol (warning-only)
if command -v "$MINGW_PREFIX/$TARGET/bin/nm" >/dev/null 2>&1; then
  echo "[INFO] Checking for __chkstk_ms in libgcc.a…"
  if "$MINGW_PREFIX/$TARGET/bin/nm" "$LIBGCC_BUILD_DIR/libgcc.a" 2>/dev/null | grep -E '__chkstk_ms|___chkstk_ms' >/dev/null; then
    echo "[OK] __chkstk_ms present in libgcc.a"
  else
    echo "[WARN] __chkstk_ms not found in libgcc.a (linker may resolve from other libs)"
  fi
fi

# ---------- Link the DLL (do NOT pass dllcrt2.o manually) ----------
cd "$LIBGCC_BUILD_DIR"
mkdir -p 32/shlib

DLL_OUT="32/shlib/libgcc_s_sjlj-1.dll"
IMPLIB_TMP="32/shlib/libgcc_s.a.tmp"
DLL_TMP="$DLL_OUT.tmp"

LINK_CMD=(
  "$BUILD_DIR/./gcc/xgcc"
  -m32 -shared -nodefaultlibs
  -B"$LIB32DIR" -L"$LIB32DIR"
  -Wl,--enable-auto-image-base
  -Wl,--enable-stdcall-fixup
  -Wl,--out-implib,"$IMPLIB_TMP"
  -o "$DLL_TMP"
  -Wl,--whole-archive libgcc.a -Wl,--no-whole-archive
  -lmingwthrd -lmingw32 -lmingwex -lmoldname -lmsvcrt
  -ladvapi32 -lshell32 -luser32 -lkernel32
)

echo "[INFO] Linking libgcc_s (32-bit)…"
printf '$ %q ' "${LINK_CMD[@]}"; echo
if ! "${LINK_CMD[@]}"; then
  echo "[ERR] Link step failed."
  echo "[HINT] Ensure these *32-bit* import libs exist in $LIB32DIR (no x64 ones mixed in):"
  echo "       libmsvcrt.a libkernel32.a libadvapi32.a libshell32.a libuser32.a libmingw32.a libmingwex.a libmingwthrd.a"
  exit 3
fi

mv -f "$DLL_TMP" "$DLL_OUT"
mv -f "$IMPLIB_TMP" "32/shlib/libgcc_s.a"

echo "[OK] Built: $DLL_OUT"
echo "[OK] Implib: 32/shlib/libgcc_s.a"
exit 0
