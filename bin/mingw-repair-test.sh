#!/data/data/com.termux/files/usr/bin/bash
# mingw-repair-and-test.sh (v2)
# Ensures MinGW sysroots, builds CRT/import-libs with proper GNU dlltool present,
# builds libunwind, creates libgcc shims, and runs link sanity tests.

T64=x86_64-w64-mingw32
T32=i686-w64-mingw32

MINGW_PREFIX="${MINGW_PREFIX:-$HOME/opt/mingw}"
SYS64="$MINGW_PREFIX/$T64"
SYS32="$MINGW_PREFIX/$T32"

LLVM_SRC="${LLVM_SRC:-$HOME/src/llvm-project}"

# Make sure MinGW binutils (dlltool etc.) are visible
export PATH="$MINGW_PREFIX/bin:$PATH"

# Find Clang resource dir (compiler-rt builtins)
if [ -z "$RD" ]; then
  for base in "$HOME/opt/android-ndk-r27b" "$HOME/opt/android-sdk/ndk/latest"; do
    d="$base/toolchains/llvm/prebuilt/linux-x86_64/lib/clang"
    [ -d "$d" ] || continue
    v=$(ls "$d" 2>/dev/null | sort -V | tail -n1)
    [ -n "$v" ] && [ -d "$d/$v" ] && RD="$d/$v" && break
  done
fi
[ -n "$RD" ] || { echo "[ERR] Could not locate Clang resource dir. Set RD."; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "[ERR] Missing: $1"; exit 1; }; }
need clang; need llvm-ar; need llvm-ranlib; need cmake; need ninja; need make

echo "== Using =="
echo "MINGW_PREFIX = $MINGW_PREFIX"
echo "SYS64        = $SYS64"
echo "SYS32        = $SYS32"
echo "LLVM_SRC     = $LLVM_SRC"
echo "RD           = $RD"
echo "PATH         = $PATH"

fatal() { echo "[FATAL] $*"; exit 1; }
run()   { echo "+ $*"; eval "$@"; return $?; }

have_min_sysroot() {
  local root="$1"
  [ -d "$root/include" ] && [ -d "$root/lib" ] || return 1
  ls "$root/lib"/libmsvcrt*.a >/dev/null 2>&1 || return 1
  ls "$root/lib"/libmingw32.a >/dev/null 2>&1 || return 1
  ls "$root/lib"/libmingwex.a  >/dev/null 2>&1 || return 1
  return 0
}

probe_symbols() {
  local root="$1" arch="$2"
  echo "== Probing required symbols ($arch) =="
  local ok=1
  for pair in \
    "libmingw32.a:_pei386_runtime_relocator" \
    "libmsvcrt.a:_initterm" \
    "libmsvcrt.a:__p__fmode" \
    "libmsvcrt.a:__p__commode" \
    "libmingwex.a:__mingw_setusermatherr"
  do
    lib="${pair%%:*}"; sym="${pair##*:}"
    if ! llvm-nm -g --defined-only "$root/lib/$lib" 2>/dev/null | grep -q "$sym"; then
      echo "[WARN] $arch: missing $sym in $lib"
      ok=0
    fi
  done
  return $ok
}

# ---------- sources ----------
prepare_mingw_sources() {
  if [ -n "$MINGW_SRC" ] && [ -d "$MINGW_SRC/mingw-w64-crt" ] && [ -d "$MINGW_SRC/mingw-w64-headers" ]; then
    echo "MINGW_SRC = $MINGW_SRC"
    return 0
  fi
  if [ -d "$HOME/src/mingw-w64/mingw-w64-crt" ]; then
    MINGW_SRC="$HOME/src/mingw-w64"
    echo "MINGW_SRC = $MINGW_SRC (existing)"
    return 0
  fi
  # last resort (requires internet)
  local WRK="$HOME/build/mingw-src-min"
  mkdir -p "$WRK"
  if [ ! -d "$WRK/mingw-w64-crt" ]; then
    echo "[INFO] Fetching mingw-w64 sources (headers+crt)…"
    run "curl -L https://github.com/mingw-w64/mingw-w64/archive/refs/heads/master.tar.gz -o '$WRK/mingw.tar.gz'" || fatal "download mingw-w64"
    run "tar -xzf '$WRK/mingw.tar.gz' -C '$WRK' --strip-components=1" || fatal "extract mingw-w64"
  fi
  MINGW_SRC="$WRK"
  echo "MINGW_SRC = $MINGW_SRC (downloaded)"
}

# Verify required binutils per target
check_target_tools() {
  local tgt="$1"
  for tool in dlltool ar ranlib nm as strip windres; do
    need "$tgt-$tool"
  done
}

build_headers() {
  local tgt="$1" sys="$2"
  local bld="$HOME/build/mingw-headers-$tgt"
  rm -rf "$bld"; mkdir -p "$bld"; cd "$bld" || fatal "cd $bld"
  echo "== Headers ($tgt) =="
  run "'$MINGW_SRC/mingw-w64-headers/configure' --host='$tgt' --prefix='$sys' --enable-sdk=all --enable-secure-api" || return 1
  run "make -j$(nproc)" || return 1
  run "make install"    || return 1
}

build_crt() {
  local tgt="$1" sys="$2"
  check_target_tools "$tgt"  # <- hard fail if $tgt-dlltool etc. missing
  local bld="$HOME/build/mingw-crt-$tgt"
  rm -rf "$bld"; mkdir -p "$bld"; cd "$bld" || fatal "cd $bld"
  echo "== CRT ($tgt) =="
  local CC="clang --target=$tgt --sysroot=$sys"
  DLLTOOL="$tgt-dlltool" AR="$tgt-ar" RANLIB="$tgt-ranlib" NM="$tgt-nm" AS="$tgt-as" STRIP="$tgt-strip" WINDRES="$tgt-windres" \
  run "CC=\"$CC\" AR=\"$tgt-ar\" RANLIB=\"$tgt-ranlib\" NM=\"$tgt-nm\" AS=\"$tgt-as\" STRIP=\"$tgt-strip\" WINDRES=\"$tgt-windres\" DLLTOOL=\"$tgt-dlltool\" \
      '$MINGW_SRC/mingw-w64-crt/configure' --host='$tgt' --prefix='$sys' --with-sysroot='$sys'" || return 1
  run "make -j$(nproc) CC='$CC' AR='$tgt-ar' RANLIB='$tgt-ranlib' NM='$tgt-nm' AS='$tgt-as' STRIP='$tgt-strip' WINDRES='$tgt-windres' DLLTOOL='$tgt-dlltool'" || return 1
  run "make install" || return 1
}

ensure_min_sysroot() {
  local tgt="$1" sys="$2"
  if have_min_sysroot "$sys"; then
    echo "[OK] MinGW sysroot present: $sys"
    return 0
  fi
  echo "[INFO] (Re)building headers+CRT into $sys"
  build_headers "$tgt" "$sys" || fatal "headers $tgt"
  build_crt     "$tgt" "$sys" || fatal "crt $tgt"
  have_min_sysroot "$sys" || fatal "sysroot still incomplete: $sys"
}

build_libunwind_for() {
  local tgt="$1" sys="$2"
  local bld="$HOME/build/libunwind-$tgt"
  rm -rf "$bld"; mkdir -p "$bld"; cd "$bld" || fatal "cd $bld"
  echo "== Building libunwind ($tgt) into $sys =="
  run "cmake -S '$LLVM_SRC/libunwind' -B '$bld' -G Ninja \
      -DCMAKE_SYSTEM_NAME=Windows \
      -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_COMPILER_TARGET='$tgt' -DCMAKE_CXX_COMPILER_TARGET='$tgt' \
      -DCMAKE_SYSROOT='$sys' \
      -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
      -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON \
      -DLIBUNWIND_ENABLE_THREADS=ON -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX='$sys' -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR=include" || fatal "cmake libunwind $tgt"
  run "ninja -C '$bld' install" || fatal "install libunwind $tgt"
  [ -f "$sys/lib/libunwind.a" ] || fatal "missing $sys/lib/libunwind.a"
}

create_libgcc_shims() {
  echo "== libgcc builtins shim =="
  ( cd "$SYS64/lib" && rm -f libgcc.a && llvm-ar qc libgcc.a "$RD/lib/windows/libclang_rt.builtins-x86_64.a" && llvm-ranlib libgcc.a ) || fatal "libgcc.a x64"
  ( cd "$SYS32/lib" && rm -f libgcc.a && llvm-ar qc libgcc.a "$RD/lib/windows/libclang_rt.builtins-i386.a"    && llvm-ranlib libgcc.a ) || fatal "libgcc.a x86"

  echo "== libgcc_eh shim =="
  local TMP; TMP="$(mktemp -d)"
  cat > "$TMP/geh64.c" <<'EOF'
#ifdef __cplusplus
extern "C" {
#endif
__declspec(dllimport) long __C_specific_handler(void*, void*, void*, void*);
long _gnu_exception_handler(void* a, void* b, void* c, void* d){
  return __C_specific_handler(a,b,c,d);
}
#ifdef __cplusplus
}
#endif
EOF
  cat > "$TMP/geh32.c" <<'EOF'
#ifdef __cplusplus
extern "C" {
#endif
__declspec(dllimport) long __stdcall __C_specific_handler(void*, void*, void*, void*);
long __stdcall _gnu_exception_handler(void* a, void* b, void* c, void* d){
  return __C_specific_handler(a,b,c,d);
}
#ifdef __cplusplus
}
#endif
EOF
  run "clang --target=$T64 --sysroot='$SYS64' -c '$TMP/geh64.c' -o '$TMP/geh64.o'" || fatal "geh64.o"
  run "clang --target=$T32 --sysroot='$SYS32' -c '$TMP/geh32.c' -o '$TMP/geh32.o'" || fatal "geh32.o"
  ( cd "$SYS64/lib" && rm -f libgcc_eh.a && llvm-ar qc libgcc_eh.a "$TMP/geh64.o" libunwind.a && llvm-ranlib libgcc_eh.a ) || fatal "libgcc_eh x64"
  ( cd "$SYS32/lib" && rm -f libgcc_eh.a && llvm-ar qc libgcc_eh.a "$TMP/geh32.o" libunwind.a && llvm-ranlib libgcc_eh.a ) || fatal "libgcc_eh x86"
  rm -rf "$TMP"
}

link_test() {
  local tgt="$1" sys="$2" src="$3" out="$4" arch="$5"
  echo "== Link test ($arch) with MinGW sysroot =="
  run "clang --target=$tgt --sysroot='$sys' -fuse-ld=lld -rtlib=compiler-rt \
    '$src' -Wl,-entry,mainCRTStartup \
    -Wl,--start-group -lmingw32 -lmingwex -lmoldname -lmsvcrt -Wl,--end-group \
    -ladvapi32 -lshell32 -luser32 -lkernel32 \
    -lgcc_eh -lgcc \
    -o '$out' -v" || return 1
  file "$out" || true
}

# ---------- main ----------
prepare_mingw_sources

# Before we build anything, make sure dlltool is really here
for t in "$T64" "$T32"; do
  if ! command -v "$t-dlltool" >/dev/null 2>&1; then
    fatal "Missing $t-dlltool. Ensure your binutils are installed in $MINGW_PREFIX/bin."
  fi
done

mkdir -p "$SYS64" "$SYS32"

ensure_min_sysroot "$T64" "$SYS64"
ensure_min_sysroot "$T32" "$SYS32"

build_libunwind_for "$T64" "$SYS64"
build_libunwind_for "$T32" "$SYS32"

create_libgcc_shims

probe_symbols "$SYS64" "x64" || echo "[WARN] x64 symbol probe had warnings"
probe_symbols "$SYS32" "x86" || echo "[WARN] x86 symbol probe had warnings"

[ -f "$HOME/t64.c" ] || cat > "$HOME/t64.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ puts("hello x64"); Sleep(10); return 0; }
EOF
[ -f "$HOME/t32.c" ] || cat > "$HOME/t32.c" <<'EOF'
#include <windows.h>
#include <stdio.h>
int main(void){ puts("hello x86"); Sleep(10); return 0; }
EOF

link_test "$T64" "$SYS64" "$HOME/t64.c" "$HOME/a64.exe" "x64" || fatal "link x64"
link_test "$T32" "$SYS32" "$HOME/t32.c" "$HOME/a32.exe" "x86" || fatal "link x86"

echo "== done =="
