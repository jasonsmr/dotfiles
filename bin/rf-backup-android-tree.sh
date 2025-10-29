#!/system/bin/sh
set -eu

SRC="$HOME/android"
DST="/sdcard/Download/BUILD"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$DST/android-tree-$TS.tar.gz"

# Create archive (includes caches to be thorough; comment lines to exclude)
echo "[backup] creating: $OUT"
tar -C "$HOME" \
  -czf "$OUT" \
  android

echo "[backup] done: $OUT"
