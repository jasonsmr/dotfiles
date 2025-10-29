#!/data/data/com.termux/files/usr/bin/bash
set -e
umask 022

# --- Paths (adjust PREFIX only if you used a different one) ---
GCCVER=13.2.0
HOME_DIR="$HOME"
BUILD="$HOME_DIR/build/gcc-android-stage1"
SRC="$HOME_DIR/src/gcc-$GCCVER"
TARGET="aarch64-linux-android"
PREFIX="$HOME_DIR/opt/toolchain/$TARGET"
DEST="$PREFIX/lib/gcc/$TARGET/$GCCVER"

# response file used only for libgcc build (no NDK headers; just GCC internals)
OVR="$BUILD/ovr-libgcc.txt"

# Avoid user aliases; keep LD_LIBRARY_PATH intact for cc1 host-libs
unalias ln 2>/dev/null || true

# Use Termux coreutils explicitly
BIN="/data/data/com.termux/files/usr/bin"
MKDIR="$BIN/mkdir"
INSTALL="$BIN/install"
LN="$BIN/ln"
LS="$BIN/ls"

# Make sure required dirs exist
$MKDIR -p "$BUILD" "$DEST"

# Response file: point to GCC's internal headers and quiet Clang-only nullability attrs
cat > "$OVR" <<EOF
-isystem $BUILD/gcc/include
-isystem $SRC/gcc/ginclude
-D__ANDROID_API__=28
-D_Nonnull=
-D_Nullable=
-D_Null_unspecified=
EOF

echo "[1/4] Clean libgcc state..."
rm -f "$BUILD/$TARGET/libgcc/"*.{o,a,d} \
      "$BUILD/$TARGET/libgcc/config.cache" \
      "$BUILD/$TARGET/libgcc/config.log" 2>/dev/null || true
rm -rf "$BUILD/gcc/include-fixed" || true

echo "[2/4] Build libgcc (freestanding)…"
make -C "$BUILD" -j1 V=1 all-target-libgcc \
  CFLAGS_FOR_TARGET="@$OVR -fPIC -Dinhibit_libc -nostdinc" \
  CPPFLAGS_FOR_TARGET="@$OVR -Dinhibit_libc -nostdinc"

echo "[3/4] Install libgcc.a + compat symlink…"
$INSTALL -m 0644 -D "$BUILD/$TARGET/libgcc/libgcc.a" "$DEST/libgcc.a"
$LN -sf libgcc.a "$DEST/libgcc_eh.a"

echo "[4/4] Verify…"
$LS -lh "$DEST"/libgcc*.a
echo "✔ libgcc rebuilt and installed to $DEST"
