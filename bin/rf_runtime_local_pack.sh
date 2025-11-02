#!/usr/bin/env bash
# RobotForest runtime packer (Termux-safe: no /tmp, no pipefail)
set -euo nounset

: "${BOX64_SRC:=$HOME/opt/box64/bin/box64}"
: "${ROOT:=$PWD}"
OUTDIR="$ROOT/out/runtime"
STAGE="$ROOT/scripts/runtime/runtime_staging"
MANIFEST="$ROOT/scripts/runtime/runtime-manifest.json"

# Ensure our temp area exists and never touch /tmp
: "${TMP:=$HOME/tmp}"
mkdir -p "$TMP" "$OUTDIR"

STAMP="$(date +%Y%m%d-%H%M%S)-$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo manual)"
VER_ASSET="runtime-${STAMP}.zip"
LATEST_ASSET="runtime-latest.zip"
ZIP="$OUTDIR/$VER_ASSET"

GH_REPO="${GH_REPO:-jasonsmr/RobotForest}"
GH_TAG="${GH_TAG:-rf-runtime}"

# --- Source sanity
if [[ ! -f "$BOX64_SRC" ]]; then
  echo "ERROR: BOX64_SRC missing: $BOX64_SRC" >&2; exit 1
fi
head -c 4 "$BOX64_SRC" | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$' || { echo "ERROR: not an ELF"; exit 1; }
BYTES_SRC=$(stat -c%s "$BOX64_SRC"); echo "[stage] source size: $BYTES_SRC"
(( BYTES_SRC >= 1000000 )) || { echo "ERROR: source too small"; exit 1; }

# --- Stage as bin/… (do NOT nest under runtime/)
rm -rf "$STAGE"
mkdir -p "$STAGE/bin"
install -m 0755 "$BOX64_SRC" "$STAGE/bin/box64"

# --- Make ZIP (bin/, bin/box64)
(
  cd "$STAGE"
  zip -9 -X -r "$ZIP" bin/ >/dev/null
)
zip -T "$ZIP" >/dev/null || { echo "ERROR: zip test failed"; exit 1; }

echo "[zip] $ZIP"
unzip -l "$ZIP" | sed -n '1,12p'
unzip -p "$ZIP" bin/box64 | head -c 4 | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$'
BYTES_ENTRY="$(unzip -p "$ZIP" bin/box64 | wc -c | tr -d ' ')"
echo "[zip] entry bytes: $BYTES_ENTRY"
(( BYTES_ENTRY >= 1000000 )) || { echo "ERROR: zipped entry too small"; exit 1; }

# --- Compute SHA for manifest
SHA256="$(sha256sum "$ZIP" | awk '{print $1}')"
echo "[zip] sha256: $SHA256"

# --- Ensure release exists
gh release view "$GH_TAG" -R "$GH_REPO" >/dev/null 2>&1 || \
  gh release create "$GH_TAG" -R "$GH_REPO" -t "RobotForest runtime" -n "Auto runtime payloads"

# --- Upload versioned asset (manifest will point HERE)
cp -f "$ZIP" "$TMP/$VER_ASSET"
gh release upload "$GH_TAG" "$TMP/$VER_ASSET" -R "$GH_REPO" --clobber >/dev/null
VER_URL="https://github.com/${GH_REPO}/releases/download/${GH_TAG}/${VER_ASSET}"
echo "[manifest url] $VER_URL"

# --- Refresh stable alias (optional)
cp -f "$ZIP" "$TMP/$LATEST_ASSET"
gh release delete-asset "$GH_TAG" "$LATEST_ASSET" -R "$GH_REPO" >/dev/null 2>&1 || true
gh release upload "$GH_TAG" "$TMP/$LATEST_ASSET" -R "$GH_REPO" --clobber >/dev/null

# --- Verify versioned URL remotely
DL="$TMP/${VER_ASSET%.zip}.verify.zip"
curl -fL --retry 3 -o "$DL" "$VER_URL"
head -c 4 "$DL" | od -An -tx1 | tr -d ' \n' | grep -q '^504b0304$' || { echo "remote not a ZIP"; exit 1; }
unzip -p "$DL" bin/box64 | head -c 4 | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$' || { echo "remote lacks ELF entry"; exit 1; }

# --- Write manifest (APK embeds this)
cat > "$MANIFEST" <<JSON
{
  "url": "$VER_URL",
  "sha256": "$SHA256",
  "subdir": "runtime"
}
JSON

echo "[done] manifest -> $MANIFEST"
