#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

OUTDIR="/sdcard/Download"
SRC="$HOME/android"
STAMP="$(date +%Y%m%d-%H%M%S)"
NAME="android-snapshot-${STAMP}.tar.gz"
TMPLIST="$(mktemp)"

# Excludes: you can tweak this list
cat > "$TMPLIST" <<'EOF'
--exclude=*/.git
--exclude=*/.gradle
--exclude=*/.cxx
--exclude=*/build
--exclude=**/*.apk
--exclude=**/.externalNativeBuild
--exclude=**/.idea
EOF

mkdir -p "$OUTDIR"
echo "Creating snapshot: $OUTDIR/$NAME"
tar -C "$HOME" -czf "$OUTDIR/$NAME" $(cat "$TMPLIST") android
rm -f "$TMPLIST"
echo "Done → $OUTDIR/$NAME"
