#!/usr/bin/env bash
set -euo pipefail

: "${BOX64_SRC:=$HOME/opt/box64/bin/box64}"

ROOT="${PWD}"
OUTDIR="${ROOT}/out/runtime"
STAGE="${ROOT}/scripts/runtime/runtime_staging"
MANIFEST="${ROOT}/scripts/runtime/runtime-manifest.json"

STAMP="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short=12 HEAD || echo manual)"
ZIP="${OUTDIR}/runtime-${STAMP}.zip"

GH_REPO="${GH_REPO:-jasonsmr/RobotForest}"
GH_TAG="${GH_TAG:-rf-runtime}"
LATEST_ASSET="runtime-latest.zip"                  # optional convenience
VER_ASSET="runtime-${STAMP}.zip"                   # cache-busting, used by manifest

# Sanity
[[ -f "$BOX64_SRC" ]] || { echo "ERROR: BOX64_SRC missing: $BOX64_SRC" >&2; exit 1; }
head -c 4 "$BOX64_SRC" | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$' \
  || { echo "ERROR: not an ELF: $BOX64_SRC" >&2; exit 1; }
BYTES_SRC=$(stat -c%s "$BOX64_SRC"); echo "[stage] source size: $BYTES_SRC"
(( BYTES_SRC >= 1000000 )) || { echo "ERROR: source too small" >&2; exit 1; }

# Stage as bin/… (NOT runtime/bin)
rm -rf "$STAGE"; mkdir -p "$OUTDIR" "$STAGE/bin"
install -m 0755 "$BOX64_SRC" "$STAGE/bin/box64"

# Make zip with explicit bin/ directory entry
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

SHA256="$(sha256sum "$ZIP" | awk '{print $1}')"
echo "[zip] sha256: $SHA256"

# Ensure release exists
gh release view "$GH_TAG" -R "$GH_REPO" >/dev/null 2>&1 || \
  gh release create "$GH_TAG" -R "$GH_REPO" -t "RobotForest runtime" -n "Auto runtime payloads"

# Upload versioned asset (the one the manifest will point at)
cp -f "$ZIP" "$HOME/tmp/$VER_ASSET"
gh release upload "$GH_TAG" "$HOME/tmp/$VER_ASSET" -R "$GH_REPO" --clobber >/dev/null
VER_URL="https://github.com/${GH_REPO}/releases/download/${GH_TAG}/${VER_ASSET}"

# Optional: also maintain a stable alias (may be cached by CDN)
cp -f "$ZIP" "$HOME/tmp/$LATEST_ASSET"
gh release delete-asset "$GH_TAG" "$LATEST_ASSET" -R "$GH_REPO" >/dev/null 2>&1 || true
gh release upload "$GH_TAG" "$HOME/tmp/$LATEST_ASSET" -R "$GH_REPO" --clobber >/dev/null

# Verify the versioned URL (avoid CDN stale)
DL="$HOME/tmp/runtime-${STAMP}.verify.zip"
curl -fL --retry 3 -o "$DL" "$VER_URL"
head -c 4 "$DL" | od -An -tx1 | tr -d ' \n' | grep -q '^504b0304$' || { file "$DL"; echo "remote not a ZIP"; exit 1; }
unzip -p "$DL" bin/box64 | head -c 4 | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$' || { echo "remote lacks ELF entry"; exit 1; }

# Manifest points at the VERSIONED asset; subdir=runtime (final path: app_runtime/runtime/bin/box64)
cat > "$MANIFEST" <<JSON
{
  "url": "$VER_URL",
  "sha256": "$SHA256",
  "subdir": "runtime"
}
JSON

echo "[done] manifest -> $MANIFEST"
