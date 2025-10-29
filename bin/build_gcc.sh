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
Good catch — that failure means the script ran from a directory that doesn’t have ./configure. You’re building out-of-tree, so we must point to the GCC source configure (e.g. ~/src/gcc-13.2.0/configure) and also anchor execution to the script’s own folder so make -C gcc runs in the right build dir.

I also switched to the *_FOR_BUILD variables (these are the ones GCC’s build system actually uses for the gen* tools), keep -nostdinc{,++} for them, and still force them on the make command line. This should stop Termux headers from leaking in.

Drop this over your ./build_gcc.sh and run it from your build directory:

#!/usr/bin/env bash

# ---------- logging (append) ----------
LOG="/sdcard/Download/gcc_build.log"
mkdir -p "$(dirname "$LOG")"
ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { printf "[%s] %s\n" "$(ts)" "$*" | tee -a "$LOG"; }
run() { log "$*"; eval "$@" 2>&1 | tee -a "$LOG"; }

log "========== NEW RUN =========="

# ---------- ensure we operate from the script's directory (the build dir) ----------
cd "$(dirname "$0")"

# ---------- locate GCC source tree (adjust if yours lives elsewhere) ----------
: "${SRC:=$HOME/src/gcc-13.2.0}"
if [ ! -x "$SRC/configure" ]; then
  for cand in "$PWD/../src/gcc-13.2.0" "$PWD/../../src/gcc-13.2.0" "$HOME/src/gcc-13.2.0"; do
    if [ -x "$cand/configure" ]; then SRC="$cand"; break; fi
  done
fi
if [ ! -x "$SRC/configure" ]; then
  log "ERROR: cannot find GCC source 'configure'. Set SRC=/path/to/gcc-13.2.0 and retry."
  exit 1
fi
log "SRC=$SRC"

# ---------- paths ----------
NDK="$HOME/opt/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64"
SYSROOT="$NDK/sysroot"
LIBCXX="$SYSROOT/usr/include/c++/v1"
INSTALL_PREFIX="$HOME/opt/toolchain/aarch64-linux-android"

# ---------- host compilers (final gcc targets Android) ----------
export CC="$NDK/bin/aarch64-linux-android28-clang --sysroot=$SYSROOT"
export CXX="$NDK/bin/aarch64-linux-android28-clang++ --sysroot=$SYSROOT -stdlib=libc++"

# ---------- build-side compilers (for gen* tools that run on the build machine) ----------
export CC_FOR_BUILD="$NDK/bin/clang --target=aarch64-linux-android28 --sysroot=$SYSROOT"
export CXX_FOR_BUILD="$NDK/bin/clang++ --target=aarch64-linux-android28 --sysroot=$SYSROOT -stdlib=libc++"

# ---------- normal flags (host) ----------
export CFLAGS="-D_GNU_SOURCE"
export CPPFLAGS="-I$LIBCXX -D_GNU_SOURCE"
export CXXFLAGS="-I$LIBCXX -nostdinc++ -isystem $LIBCXX -D_GNU_SOURCE"

# ---------- CRITICAL: flags for the generator tools ----------
CPPFLAGS_FOR_BUILD="-D_GNU_SOURCE -DUSE_UNLOCKED_IO=0 -nostdinc -isystem $SYSROOT/usr/include -isystem $LIBCXX"
CFLAGS_FOR_BUILD="-D_GNU_SOURCE -DUSE_UNLOCKED_IO=0"
CXXFLAGS_FOR_BUILD="-D_GNU_SOURCE -DUSE_UNLOCKED_IO=0 -nostdinc++ -isystem $LIBCXX -isystem $SYSROOT/usr/include"
LDFLAGS_FOR_BUILD="--sysroot=$SYSROOT"

# ---------- bionic knobs (avoid *_unlocked on Android) ----------
export ac_cv_have_decl_strsignal=yes
export ac_cv_have_decl_basename=yes
export ac_cv_func_fputc_unlocked=no ac_cv_have_decl_fputc_unlocked=no
export ac_cv_func_fgetc_unlocked=no ac_cv_have_decl_fgetc_unlocked=no

# ---------- hygiene ----------
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH PKG_CONFIG_PATH || true
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"

# ---------- log summary ----------
log "NDK=$NDK"
log "SYSROOT=$SYSROOT"
log "LIBCXX=$LIBCXX"
log "INSTALL_PREFIX=$INSTALL_PREFIX"
log "CC=$CC"
log "CXX=$CXX"
log "CC_FOR_BUILD=$CC_FOR_BUILD"
log "CXX_FOR_BUILD=$CXX_FOR_BUILD"
log "CPPFLAGS_FOR_BUILD=$CPPFLAGS_FOR_BUILD"
log "CFLAGS_FOR_BUILD=$CFLAGS_FOR_BUILD"
log "CXXFLAGS_FOR_BUILD=$CXXFLAGS_FOR_BUILD"
log "LDFLAGS_FOR_BUILD=$LDFLAGS_FOR_BUILD"

# ---------- clean stale gcc state (ok if first run) ----------
run "make -C gcc distclean || true"
run "rm -rf gcc/build.* gcc/config.cache gcc/config.log 2>/dev/null || true"

# ---------- configure (out-of-tree) ----------
if [ ! -f Makefile ] || ! grep -q "$INSTALL_PREFIX" Makefile; then
  run "'$SRC'/configure \
    --prefix='$INSTALL_PREFIX' \
    --build=aarch64-unknown-linux-gnu \
    --host=aarch64-unknown-linux-android \
    --target=aarch64-linux-android \
    --with-sysroot='$SYSROOT' \
    --with-build-sysroot='$SYSROOT' \
    --disable-bootstrap \
    --disable-nls \
    --enable-languages=c,c++ \
    --without-isl \
    NATIVE_SYSTEM_HEADER_DIR=/nonexistent"
else
  log "Top-level already configured for $INSTALL_PREFIX; skipping configure"
fi

# ---------- configure gcc subdir with *_FOR_BUILD visible ----------
run "make -j1 configure-gcc \
  CC_FOR_BUILD='$CC_FOR_BUILD' \
  CXX_FOR_BUILD='$CXX_FOR_BUILD' \
  CPPFLAGS_FOR_BUILD='$CPPFLAGS_FOR_BUILD' \
  CFLAGS_FOR_BUILD='$CFLAGS_FOR_BUILD' \
  CXXFLAGS_FOR_BUILD='$CXXFLAGS_FOR_BUILD' \
  LDFLAGS_FOR_BUILD='$LDFLAGS_FOR_BUILD'"

test -f gcc/Makefile && log "OK: gcc/Makefile present" || { log "ERROR: gcc/Makefile missing"; exit 1; }

# ---------- build gcc (force *_FOR_BUILD on cmdline; V=1 for visibility) ----------
CPU="$(nproc 2>/dev/null || echo 1)"
run "make -j'$CPU' V=1 all-gcc \
  CC_FOR_BUILD='$CC_FOR_BUILD' \
  CXX_FOR_BUILD='$CXX_FOR_BUILD' \
  CPPFLAGS_FOR_BUILD='$CPPFLAGS_FOR_BUILD' \
  CFLAGS_FOR_BUILD='$CFLAGS_FOR_BUILD' \
  CXXFLAGS_FOR_BUILD='$CXXFLAGS_FOR_BUILD' \
  LDFLAGS_FOR_BUILD='$LDFLAGS_FOR_BUILD'"

log "=========== DONE ==========="

What this fixes:

./configure: No such file → we call "$SRC/configure" from your source tree.

Running in the wrong directory → cd "$(dirname "$0")" anchors the script to the build dir.

Gen tools pulling in Termux headers → uses CPPFLAGS_FOR_BUILD/CXXFLAGS_FOR_BUILD with -nostdinc{,++} and only $SYSROOT/$LIBCXX, and we pass them to both configure-gcc and make all-gcc.

Extra guard: NATIVE_SYSTEM_HEADER_DIR=/nonexistent to discourage GCC from guessing local headers.


After running, check /sdcard/Download/gcc_build.log. In the long compile lines for gcc/genhooks.cc, gcc/genmodes.cc, gcc/gengtype-*.cc you should now see -nostdinc/-nostdinc++ and only $SYSROOT/usr/include + $LIBCXX — and you should not see /data/data/com.termux/files/usr/include. If any one line still shows the Termux path, paste that one compile line and I’ll tighten the knobs further.


