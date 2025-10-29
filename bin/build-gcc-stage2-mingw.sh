#!/usr/bin/env sh
. "$HOME/bin/env-cross.sh"

GCC_VER="${GCC_VER:-13.2.0}"
GCCSRC="$SRC/gcc-$GCC_VER"

for T in "$T64" "$T32"; do
  INST="$XPREFIX/$T"
  BDIR="$BUILD/gcc-$GCC_VER-$T-stage2"
  mkdir -p "$BDIR"
  cd "$BDIR" || exit 1

  "$GCCSRC/configure" \
    --build=aarch64-unknown-linux-android \
    --host=aarch64-unknown-linux-android \
    --target="$T" \
    --prefix="$INST" \
    --disable-nls --disable-multilib \
    --enable-languages=c,c++ \
    --without-isl \
    --disable-libgomp --disable-libsanitizer --disable-libvtv --disable-libquadmath \
    --with-native-system-header-dir="$INST/$T/include" || exit 1

  make $J1 all || exit 1
  make install || exit 1
done

echo ">> Full MinGW GCC toolchains ready (C/C++)"
