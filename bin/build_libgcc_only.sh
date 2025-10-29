#!/data/data/com.termux/files/usr/bin/sh
set -e

# --- paths you already use; change only if your layout differs ---
BUILD="$HOME/build/gcc-android-stage1"
SRC="$HOME/src/gcc-13.2.0"
PREFIX="$HOME/opt/toolchain/aarch64-linux-android"
GCCVER="13.2.0"

# Host libs for cc1 (mpc/mpfr/gmp)
export LD_LIBRARY_PATH="$HOME/opt/host-libs/lib${LD_LIBRARY_PATH+:$LD_LIBRARY_PATH}"

# Response file: USE ONLY GCC INTERNAL HEADERS (no NDK here)
OVR="$BUILD/ovr-libgcc.txt"
cat > "$OVR" <<EOF
-isystem $BUILD/gcc/include
-isystem $SRC/gcc/ginclude
-D__ANDROID_API__=28
-D_Nonnull=
-D_Nullable=
-D_Null_unspecified=
EOF

echo "[1/3] Clean a bit…"
rm -f "$BUILD/aarch64-linux-android/libgcc/"*.d \
      "$BUILD/aarch64-linux-android/libgcc/config.cache" \
      "$BUILD/aarch64-linux-android/libgcc/config.log" 2>/dev/null || true

# IMPORTANT: do NOT add --sysroot or any NDK -isystem here
echo "[2/3] Build ONLY libgcc.a (no libgcov)…"
env -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH -u OBJC_INCLUDE_PATH \
  make -C "$BUILD" -j1 V=1 aarch64-linux-android/libgcc/libgcc.a \
    CFLAGS_FOR_TARGET="@$OVR -fPIC -Dinhibit_libc" \
    CPPFLAGS_FOR_TARGET="@$OVR -Dinhibit_libc"

# Install manually (don’t call install-target-libgcc: that re-enters libgcov)
DEST="$PREFIX/lib/gcc/aarch64-linux-android/$GCCVER"
echo "[3/3] Install libgcc.a… -> $DEST"
mkdir -p "$DEST"
cp -a "$BUILD/aarch64-linux-android/libgcc/libgcc.a" "$DEST/libgcc.a"
ln -sf libgcc.a "$DEST/libgcc_eh.a"

# Show result
ls -lh "$DEST"/libgcc*.a
echo "Done ✔"
