#!/data/data/com.termux/files/usr/bin/env zsh
set -e

# ---- paths
: ${CRT_SRC:="$HOME/src/mingw-w64/mingw-w64-crt"}
: ${HDR_SRC:="$HOME/src/mingw-w64/mingw-w64-headers"}
: ${CRT_BLD:="$HOME/build/crt-x86_64-w64-mingw32"}
: ${TARGET:="x86_64-w64-mingw32"}
: ${PREFIX:="${CRT_BLD%/*}"}                     # <— keep installs under $HOME/build
SYSROOT="$PREFIX/$TARGET"

# prefer NDK toolchain
NDK_PREBUILT="$HOME/opt/android-sdk/ndk/latest/toolchains/llvm/prebuilt/linux-aarch64"
LLVM_BIN="$NDK_PREBUILT/bin"
[[ -x "$LLVM_BIN/clang" ]] || LLVM_BIN="$(dirname "$(command -v clang || true)")"

CLANG="$LLVM_BIN/clang"
LLVM_AR="${LLVM_BIN}/llvm-ar";      [[ -x $LLVM_AR      ]] || LLVM_AR="$(command -v llvm-ar   || command -v ar     || true)"
LLVM_RANLIB="${LLVM_BIN}/llvm-ranlib"; [[ -x $LLVM_RANLIB ]] || LLVM_RANLIB="$(command -v llvm-ranlib || command -v ranlib || true)"
LLVM_AS="${LLVM_BIN}/llvm-as";      [[ -x $LLVM_AS      ]] || LLVM_AS="$(command -v llvm-as   || true)"
DLLTOOL_BIN="${LLVM_BIN}/llvm-dlltool"; [[ -x $DLLTOOL_BIN ]] || DLLTOOL_BIN="$(command -v llvm-dlltool || command -v dlltool || true)"

# ---- logging
LOGDIR="$HOME/logs"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/mingw-crt-bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

say()  { print -- "[bootstrap] $*"; }
warn() { print -u2 -- "[bootstrap][WARN] $*"; }
die()  { print -u2 -- "[bootstrap][FATAL] $*"; exit 1; }

say "log: $LOG"
say "CRT_SRC=$CRT_SRC"
say "HDR_SRC=$HDR_SRC"
say "CRT_BLD=$CRT_BLD"
say "PREFIX=$PREFIX"
say "SYSROOT=$SYSROOT"
say "LLVM_BIN=$LLVM_BIN"
say "DLLTOOL_BIN=$DLLTOOL_BIN"

[[ -d "$CRT_SRC" ]] || die "missing CRT source dir"
[[ -d "$HDR_SRC" ]] || die "missing headers source dir"
[[ -x "$CLANG"    ]] || die "clang not found"
[[ -x "$LLVM_AR"  ]] || die "llvm-ar/ar not found"
[[ -x "$LLVM_RANLIB" ]] || die "llvm-ranlib/ranlib not found"
[[ -x "$DLLTOOL_BIN" ]] || die "llvm-dlltool/dlltool not found"

mkdir -p "$CRT_BLD" "$CRT_BLD/lib32" "$SYSROOT"

# ---- 1) install headers into SYSROOT (with auto-clean of source dir)
need_headers=0
for f in stdio.h stdlib.h string.h stdint.h stddef.h; do
  [[ -f "$SYSROOT/include/$f" ]] || need_headers=1
done

if (( need_headers )); then
  say "== cleaning headers source (avoid in-tree leftovers) =="
  ( cd "$HDR_SRC" && make distclean >/dev/null 2>&1 || true; rm -f config.{cache,status} ) || true

  say "== installing mingw-w64 headers into $SYSROOT =="
  HDR_BLD="$PREFIX/headers-$TARGET"; mkdir -p "$HDR_BLD"
  cd "$HDR_BLD"
  rm -f config.cache
  CC="$CLANG --target=$TARGET --sysroot=$SYSROOT" \
  AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" \
  "$HDR_SRC/configure" \
     --host="$TARGET" \
     --prefix="$SYSROOT" \
     --with-default-msvcrt=ucrt \
     --enable-sdk=all
  make -j"$(nproc)"
  make install
else
  say "== headers already present in $SYSROOT/include =="
fi

# sanity
for f in stdio.h stdlib.h; do
  [[ -f "$SYSROOT/include/$f" ]] || die "still missing $f in $SYSROOT/include"
done

# ---- 2) configure CRT against that same SYSROOT
say "== configure mingw-w64-crt =="
cd "$CRT_BLD"; rm -f config.cache
CC="$CLANG --target=$TARGET --sysroot=$SYSROOT" \
AR="$LLVM_AR" RANLIB="$LLVM_RANLIB" AS="$LLVM_AS" \
DLLTOOL="$DLLTOOL_BIN" \
"$CRT_SRC/configure" \
  --host="$TARGET" \
  --prefix="$PREFIX" \
  --disable-silent-rules
say "configure done."

# ---- helpers to pre-seed MRI prerequisites
mk_def_from_common() {
  local name="$1" out="$CRT_BLD/lib32/${name}.def"
  local d1="$CRT_SRC/lib-common/${name}.def"
  local d2="$CRT_SRC/lib-common/${name}.def.in"
  [[ -f "$out" ]] && { print -- "$out"; return 0; }
  if [[ -f "$d1" ]]; then cp -f "$d1" "$out"
  elif [[ -f "$d2" ]]; then
    "$CLANG" -E -x c "$d2" -Wp,-w -undef -P -I "$CRT_SRC/def-include" -DDEF_I386 -o "$out"
  else warn "no def(.in) for $name"; return 1; fi
  print -- "$out"
}
mk_implib() {
  local def="$1" out="$2" mach="${3:-i386}"
  mkdir -p "${out:h}"
  say "dlltool -m $mach  -d ${def:t} -> ${out:t}"
  "$DLLTOOL_BIN" -m "$mach" -d "$def" -l "$out"
}

# ---- 3) seed import libs
say "== seeding lib32 import libraries =="
for n in avifil32 avicap32 msvfw32; do
  out="$CRT_BLD/lib32/lib${n}.a"
  [[ -f "$out" ]] || { def="$CRT_SRC/lib32/${n}.def"; [[ -f "$def" ]] && mk_implib "$def" "$out" i386 || warn "missing $def"; }
done

types=( conio convert environment filesystem heap locale math multibyte private process runtime stdio string time utility )
for t in $types; do
  out="$CRT_BLD/lib32/libapi-ms-win-crt-${t}-l1-1-0.a"
  [[ -f "$out" ]] && continue
  def="$(mk_def_from_common "api-ms-win-crt-${t}-l1-1-0")" || continue
  mk_implib "$def" "$out" i386 || warn "failed ${out:t}"
done

for n in api-ms-win-appmodel-runtime-l1-1-1 api-ms-win-appmodel-runtime-l1-1-0; do
  out="$CRT_BLD/lib32/lib${n}.a"
  [[ -f "$out" ]] && continue
  def="$(mk_def_from_common "$n")" || { warn "no def for $n"; continue; }
  mk_implib "$def" "$out" i386 || warn "failed ${out:t}"
done

msvcrt_def_a="$CRT_BLD/lib32/libmsvcrt_def.a"
if [[ ! -f "$msvcrt_def_a" ]]; then
  d="$(mk_def_from_common msvcrt)" || warn "no def for msvcrt"
  [[ -n "$d" ]] && mk_implib "$d" "$msvcrt_def_a" i386 || true
fi

# ---- 4) build troublesome meta-archives serialized
say "== building critical meta-archives (serialized) =="
make -C "$CRT_BLD" -j1 DLLTOOL="$DLLTOOL_BIN" lib32/libvfw32.a || true
make -C "$CRT_BLD" -j1 DLLTOOL="$DLLTOOL_BIN" lib32/libucrt.a || true
make -C "$CRT_BLD" -j1 DLLTOOL="$DLLTOOL_BIN" lib32/libwindowscoreheadless_apiset.a || true

# ---- 5) full CRT build + install
say "== full build =="
make -C "$CRT_BLD" -j"$(nproc)" DLLTOOL="$DLLTOOL_BIN"
say "== install =="
make -C "$CRT_BLD" install DLLTOOL="$DLLTOOL_BIN"

say "done at $(date)"
