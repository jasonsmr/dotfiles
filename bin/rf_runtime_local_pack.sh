#!/usr/bin/env bash
# NOTE: bash, no pipefail; Termux has /data/.../usr/bin/bash
set -eu

: "${BOX64_SRC:=$HOME/opt/box64/bin/box64}"
: "${GH_REPO:=jasonsmr/RobotForest}"
: "${GH_TAG:=rf-runtime}"

ROOT="${PWD}"
OUTDIR="${ROOT}/out/runtime"
STAGE="${ROOT}/scripts/runtime/runtime_staging"
MANIFEST="${ROOT}/scripts/runtime/runtime-manifest.json"

STAMP="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short=12 HEAD || echo manual)"
VER_ASSET="runtime-${STAMP}.zip"
LATEST_ASSET="runtime-latest.zip"
ZIP="${OUTDIR}/${VER_ASSET}"

# Ensure tmp dir exists (you hit missing file earlier)
mkdir -p "$HOME/tmp" "$OUTDIR" "$STAGE/bin"

# --- Source sanity
[ -f "$BOX64_SRC" ] || { echo "ERROR: BOX64_SRC missing: $BOX64_SRC" >&2; exit 1; }
head -c 4 "$BOX64_SRC" | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$' || { echo "ERROR: not an ELF: $BOX64_SRC" >&2; exit 1; }

# --- Stage + zip (root = bin/)
rm -rf "$STAGE/bin" && mkdir -p "$STAGE/bin"
install -m 0755 "$BOX64_SRC" "$STAGE/bin/box64"
( cd "$STAGE" && zip -9 -X -r "$ZIP" bin/ >/dev/null )
zip -T "$ZIP" >/dev/null

SHA256="$(sha256sum "$ZIP" | awk '{print $1}')"

# --- Release exists?
gh release view "$GH_TAG" -R "$GH_REPO" >/dev/null 2>&1 || \
  gh release create "$GH_TAG" -R "$GH_REPO" -t "RobotForest runtime" -n "Auto runtime payloads"

# --- Upload versioned asset
cp -f "$ZIP" "$HOME/tmp/$VER_ASSET"
gh release upload "$GH_TAG" "$HOME/tmp/$VER_ASSET" -R "$GH_REPO" --clobber >/dev/null
VER_URL="https://github.com/${GH_REPO}/releases/download/${GH_TAG}/${VER_ASSET}"
echo "[manifest url] $VER_URL"

# --- Refresh stable alias (optional but convenient)
cp -f "$ZIP" "$HOME/tmp/$LATEST_ASSET"
gh release delete-asset "$GH_TAG" "$LATEST_ASSET" -R "$GH_REPO" >/dev/null 2>&1 || true
gh release upload "$GH_TAG" "$HOME/tmp/$LATEST_ASSET" -R "$GH_REPO" --clobber >/dev/null

# --- Verify versioned URL is a proper ZIP with bin/box64 ELF
DL="$HOME/tmp/${VER_ASSET%.zip}.verify.zip"
curl -fL --retry 3 -o "$DL" "$VER_URL"
head -c 4 "$DL" | od -An -tx1 | tr -d ' \n' | grep -q '^504b0304$' || { echo "remote not a ZIP"; exit 1; }
unzip -p "$DL" bin/box64 | head -c 4 | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$' || { echo "remote lacks ELF entry"; exit 1; }

# --- Write manifest with VERSIONED URL
cat > "$MANIFEST" <<JSON
{
  "url": "$VER_URL",
  "sha256": "$SHA256",
  "subdir": "runtime"
}
JSON

echo "[done] manifest -> $MANIFEST"
