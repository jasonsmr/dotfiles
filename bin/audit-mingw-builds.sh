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

# --- CONFIG ------------------------------------------------------------
PREFIX="${PREFIX:-$HOME/opt/mingw}"
TARGET="${TARGET:-x86_64-w64-mingw32}"
HOST_LIBDIR="/data/data/com.termux/files/usr/lib"      # Termux host libs
HOST_ZSTD="$HOST_LIBDIR/libzstd.so.1"

# Where to scan for builds. Add/remove as you like.
CANDIDATE_ROOTS=(
  "$HOME/src/mingw-w64/mingw-w64-headers"
  "$HOME/src/mingw-w64/mingw-w64-crt"
  "$HOME/src/mingw-w64/mingw-w64-libraries/winpthreads"
  "$HOME/build/gcc-mingw-stage1"
  "$HOME/build/gcc-13.2.0-stage2"
  "$HOME/toolchain-work/build"       # you had some earlier attempts here
)
# ----------------------------------------------------------------------

say() { printf '%s\n' "$*"; }
hr() { printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" '' | tr ' ' '-'; }

say "== Host runtime check (libzstd) =="
if [ -e "$HOST_ZSTD" ]; then
  say "✔ Found: $HOST_ZSTD"
else
  say "✖ Missing: $HOST_ZSTD"
  say "  Try: pkg install libzstd"
  say "  (If mirrors glitch, run: pkg up && pkg install libzstd)"
fi
hr

# Can we run objdump right now?
OBJDUMP_OK=0
if command -v "$TARGET-objdump" >/dev/null 2>&1; then
  if "$TARGET-objdump" --version >/dev/null 2>&1; then
    OBJDUMP_OK=1
  else
    say "Note: $TARGET-objdump exists but can’t run (likely due to missing libzstd)."
  fi
else
  say "Note: $TARGET-objdump not found in PATH=$PATH"
fi
hr

say "== Audit: config.log compilers =="
BAD=0
GOOD=0
NULL=0

# Build up a list of config.log files
mapfile -t LOGS < <(
  for root in "${CANDIDATE_ROOTS[@]}"; do
    [ -d "$root" ] || continue
    # common patterns: build dirs and the source roots (some projects log in-tree)
    find "$root" -type f -name config.log 2>/dev/null
  done
)

if [ "${#LOGS[@]}" -eq 0 ]; then
  say "No config.log files found under the configured roots."
else
  for log in "${LOGS[@]}"; do
    echo
    say "-- $log --"
    # What configure thinks:
    grep -E '^CC=|^CXX=|checking for .*gcc|checking for .*g\+\+' -n "$log" || true
    # Smoking gun: any Android NDK clang path
    if grep -qE '/android.*/clang' "$log"; then
      say ">>> SUSPECT: Android NDK clang detected in this config.log"
      BAD=$((BAD+1))
      # show the offending lines
      grep -nE '/android.*/clang' "$log" || true
    else
      # If CC/CXX are present, assume good; else unknown
      if grep -qE '^CC=|^CXX=' "$log"; then
        say "OK: no Android clang references found."
        GOOD=$((GOOD+1))
      else
        say "WARN: couldn’t determine CC/CXX from this log."
        NULL=$((NULL+1))
      fi
    fi
  done
fi
hr
say "Summary: $GOOD ok, $BAD suspect, $NULL unknown"
hr

say "== Target lib sanity (if any built) =="
LIBDIR="$PREFIX/$TARGET/lib"
if [ -d "$LIBDIR" ]; then
  shopt -s nullglob
  LIBS=("$LIBDIR"/*.a)
  if [ "${#LIBS[@]}" -eq 0 ]; then
    say "No static libs found yet in $LIBDIR (CRT/winpthreads probably not installed yet)."
  else
    say "Inspecting first few libs with 'file':"
    i=0
    for a in "${LIBS[@]}"; do
      file "$a" || true
      i=$((i+1))
      [ "$i" -ge 10 ] && break
    done

    if [ "$OBJDUMP_OK" -eq 1 ]; then
      # Try a targeted objdump on common libs if present
      for cand in libwinpthread.a libmingw32.a libmsvcrt.a; do
        if [ -e "$LIBDIR/$cand" ]; then
          echo
          say "objdump -f $cand:"
          "$TARGET-objdump" -f "$LIBDIR/$cand" | sed -n '1,10p' || true
        fi
      done
    else
      say "Skipping objdump checks (host objdump unavailable or can’t run)."
    fi
  fi
else
  say "Lib directory not found: $LIBDIR (install CRT/winpthreads first)."
fi

echo
hr
say "Next steps:"
cat <<'TIP'

1) If any package was marked "SUSPECT", rebuild it clean with your MinGW cross tools:
   # Example (winpthreads):
   cd "$HOME/src/mingw-w64/mingw-w64-libraries/winpthreads"
   rm -rf build && mkdir build && cd build
   export PREFIX="$HOME/opt/mingw"; export TARGET=x86_64-w64-mingw32
   export PATH="$PREFIX/bin:$PATH"
   export CC=$TARGET-gcc CXX=$TARGET-g++ AR=$TARGET-ar RANLIB=$TARGET-ranlib \
          NM=$TARGET-nm AS=$TARGET-as DLLTOOL=$TARGET-dlltool WINDRES=$TARGET-windres
   export CPPFLAGS="-I$PREFIX/$TARGET/include"
   ../configure --host=$TARGET --prefix="$PREFIX/$TARGET" --enable-static --enable-shared
   make -j"$(nproc)"
   make install

2) For mingw-w64-crt (common failure point), do:
   cd "$HOME/src/mingw-w64/mingw-w64-crt"
   rm -rf build && mkdir build && cd build
   export PREFIX="$HOME/opt/mingw"; export TARGET=x86_64-w64-mingw32
   export PATH="$PREFIX/bin:$PATH"
   export CC=$TARGET-gcc CXX=$TARGET-g++ AR=$TARGET-g++ AR=$TARGET-ar RANLIB=$TARGET-ranlib \
          NM=$TARGET-nm AS=$TARGET-as DLLTOOL=$TARGET-dlltool WINDRES=$TARGET-windres
   export CPPFLAGS="-I$PREFIX/$TARGET/include"
   ../configure --host=$TARGET --prefix="$PREFIX/$TARGET" --with-sysroot="$PREFIX/$TARGET" --disable-lib32
   make -j"$(nproc)"
   make install

3) Host library issue (objdump fails with "libzstd.so.1 not found"):
   pkg up
   pkg install libzstd
   # Verify it exists:
   ls -l /data/data/com.termux/files/usr/lib/libzstd.so.1

4) To audit again later, just re-run this script.

TIP
