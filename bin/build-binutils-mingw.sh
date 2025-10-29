#!/data/data/com.termux/files/usr/bin/bash
# Build MinGW binutils (only: bfd, opcodes, gas, ld) for 64-bit and 32-bit.
# Uses sources already unpacked in ~/src/binutils-2.42

set -e  # keep it simple/portable; we avoid 'set -u' + 'pipefail' to not upset shells
: "${TRACE:=}" ; [ -n "$TRACE" ] && set -x

die(){ printf '!! %s\n' "$*" >&2; exit 1; }
msg(){ printf '>> %s\n' "$*"; }

# --- load env ---------------------------------------------------------------
ENV="${ENV:-$HOME/bin/env-cross.sh}"
[ -r "$ENV" ] || die "missing $ENV; create it first"
# shellcheck source=/dev/null
. "$ENV"

# --- configuration ----------------------------------------------------------
BINUTILS_VER=2.42
SRC_DIR="$SRC/binutils-$BINUTILS_VER"

[ -d "$SRC_DIR" ] || die "Source dir not found: $SRC_DIR
You said your sources live under ~/src and include binutils-2.42."

LOGDIR="$HOME/logs/cross"
mkdir -p "$SRC" "$BUILD" "$LOGDIR" || die "cannot create roots"
LOGFILE="$LOGDIR/binutils-$(date +%F_%H-%M-%S).log"
msg "Logging to: $LOGFILE"

# Re-assert host toolchain pinning (paranoia, in case env changed)
HOST_BIN="/data/data/com.termux/files/usr/bin"
export CC="$HOST_BIN/clang"
export CXX="$HOST_BIN/clang++"
export AR="$HOST_BIN/ar"
export RANLIB="$HOST_BIN/ranlib"
export NM="$HOST_BIN/nm"
export LD="$HOST_BIN/ld.lld"
export STRIP="$HOST_BIN/strip"
export PKG_CONFIG="$HOST_BIN/pkg-config"
export PATH="$HOST_BIN:$HOME/bin"

# Common configure flags — build only what we need right now
cfg_common=(
  --build=aarch64-unknown-linux-android
  --host=aarch64-unknown-linux-android
  --disable-nls
  --disable-werror
  --disable-gdb
  --disable-gdbserver
  --disable-sim
  --disable-gprofng
)

build_one_target() {
  local TGT="$1"
  local BDIR="$BUILD/binutils-${BINUTILS_VER}-${TGT}"
  local INST="$XPREFIX/$TGT"

  msg "=== ${TGT} : configure ==="
  mkdir -p "$BDIR" "$INST"
  cd "$BDIR"

  # Always run configure (safe to re-run); out-of-tree build
  sh "$SRC_DIR/configure" \
     "${cfg_common[@]}" \
     --target="$TGT" \
     --prefix="$INST" \
     |& tee -a "$LOGFILE"

  msg "=== ${TGT} : make core (bfd/opcodes/gas/ld) ==="
  make $J1 all-bfd all-opcodes all-gas all-ld |& tee -a "$LOGFILE"

  msg "=== ${TGT} : install core ==="
  make $J1 install-bfd install-opcodes install-gas install-ld |& tee -a "$LOGFILE"

  msg "=== ${TGT} : sanity ==="
  "$INST/bin/$TGT-as" --version  | head -n1 | tee -a "$LOGFILE"
  "$INST/bin/$TGT-ld" --version  | head -n1 | tee -a "$LOGFILE"
}

# --- run both targets -------------------------------------------------------
build_one_target "$T64"
build_one_target "$T32"

msg "Done. Binutils installed under: $XPREFIX/{${T64},${T32}}"
msg "Try:"
echo "  $XPREFIX/$T64/bin/$T64-as --version"
echo "  $XPREFIX/$T64/bin/$T64-ld --version"
echo "  $XPREFIX/$T32/bin/$T32-as --version"
echo "  $XPREFIX/$T32/bin/$T32-ld --version"
