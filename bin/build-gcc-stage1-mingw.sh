#!/usr/bin/env sh
. "$HOME/bin/env-cross.sh"

GCC_VER="${GCC_VER:-13.2.0}"
GCCSRC="$SRC/gcc-$GCC_VER"

[ -d "$GCCSRC" ] || { echo ">> Put gcc-$GCC_VER sources in $SRC"; exit 1; }

for T in "$T64" "$T32"; do
  INST="$XPREFIX/$T"
  BDIR="$BUILD/gcc-$GCC_VER-$T-stage1"
  mkdir -p "$BDIR"
  cd "$BDIR" || exit 1

  # Required: gmp/mpfr/mpc available via LD_LIBRARY_PATH (already set)
  "$GCCSRC/configure" \
    --build=aarch64-unknown-linux-android \
    --host=aarch64-unknown-linux-android \
    --target="$T" \
    --prefix="$INST" \
    --disable-nls --disable-multilib \
    --enable-languages=c \
    --without-isl \
    --disable-libgomp --disable-libquadmath --disable-libssp --disable-libsanitizer --disable-libvtv \
    --disable-shared --disable-libstdcxx \
    --with-native-system-header-dir="$INST/$T/include" || exit 1

  make $J1 all-gcc || exit 1
  make install-gcc || exit 1
done

echo ">> GCC stage1 installed (cc1 & drivers) under $XPREFIX/<triplet>"
