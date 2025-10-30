#!/usr/bin/env bash
set -euo pipefail

# Where your built box64 ELF lives (override with: BOX64_SRC=/path/to/box64)
: "${BOX64_SRC:=$HOME/opt/box64/bin/box64}"

# Toggle: force a file:// URL in the manifest even if GH_PUBLISH=1
: "${FORCE_FILE_URL:=0}"

ROOT="${PWD}"
OUTDIR="${ROOT}/out/runtime"
STAGE="${ROOT}/scripts/runtime/runtime_staging"
MANIFEST_SRC="${ROOT}/scripts/runtime/runtime-manifest.json"   # embedded into APK
MANIFEST_DST="${OUTDIR}/runtime-manifest.json"                 # for CI/inspection
STAMP="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short=12 HEAD || echo manual)"
ZIP="${OUTDIR}/runtime-${STAMP}.zip"
SHA="${ZIP}.sha256"

# Clean staging to prevent lingering stubs
rm -rf "${STAGE}"
mkdir -p "${OUTDIR}" "${STAGE}/bin"

# --- Sanity on source ELF
if [[ ! -f "${BOX64_SRC}" ]]; then
  echo "ERROR: BOX64_SRC not found: ${BOX64_SRC}" >&2
  exit 1
fi
if ! head -c 4 "${BOX64_SRC}" | hexdump -C | grep -q '7f 45 4c 46'; then
  echo "ERROR: ${BOX64_SRC} is not an ELF (missing 0x7F 'ELF' magic)" >&2
  file "${BOX64_SRC}" || true
  exit 1
fi
BYTES_SRC=$(stat -c%s "${BOX64_SRC}")
if (( BYTES_SRC < 1000000 )); then
  echo "ERROR: ${BOX64_SRC} too small (${BYTES_SRC} bytes) — expected a real build" >&2
  exit 1
fi

# --- Stage payload (exact path: bin/box64)
install -m 0755 "${BOX64_SRC}" "${STAGE}/bin/box64"

# Extra guard: confirm staged file size
BYTES_STAGE=$(stat -c%s "${STAGE}/bin/box64")
echo "[stage] bin/box64 size: ${BYTES_STAGE} bytes"
if (( BYTES_STAGE < 1000000 )); then
  echo "ERROR: staged box64 too small (${BYTES_STAGE} bytes)" >&2
  exit 1
fi

# --- Create ZIP (ensure 'bin/...' root)
( cd "${STAGE}" && zip -9 -X -r "${ZIP}" bin >/dev/null )

# --- Verify ZIP contents
echo "[runtime] staging: ${STAGE}"
echo "[runtime] out zip: ${ZIP}"
echo "[runtime] zip listing:"
zipinfo -1 "${ZIP}" | sed 's/^/  /'

# Check the entry exists and is ELF
if ! unzip -p "${ZIP}" bin/box64 | head -c 4 | hexdump -C | grep -q '7f 45 4c 46'; then
  echo "ERROR: ZIP does not contain a valid ELF at bin/box64" >&2
  exit 1
fi
BYTES_ZIP_ENTRY=$(unzip -p "${ZIP}" bin/box64 | wc -c | tr -d ' ')
echo "[runtime] zipped bin/box64 size: ${BYTES_ZIP_ENTRY} bytes"
if (( BYTES_ZIP_ENTRY < 1000000 )); then
  echo "ERROR: zipped box64 too small (${BYTES_ZIP_ENTRY} bytes)" >&2
  exit 1
fi

# --- Hash + size
SHA256="$(sha256sum "${ZIP}" | awk '{print $1}')"
echo "${SHA256}  $(basename "${ZIP}")" > "${SHA}"
ZIP_BYTES=$(stat -c%s "${ZIP}")
echo "[runtime] sha256: ${SHA256}"

# --- Optionally publish
PUB_URL=""
if [[ "${GH_PUBLISH:-}" == "1" && "${FORCE_FILE_URL}" != "1" ]]; then
  if gh repo view --json nameWithOwner >/dev/null 2>&1; then
    NWO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  else
    NWO="jasonsmr/RobotForest"
  fi
  gh release upload auto "${ZIP}" --clobber >/dev/null
  gh release upload auto "${SHA}" --clobber >/dev/null || true
  PUB_URL="https://github.com/${NWO}/releases/download/auto/$(basename "${ZIP}")"
  echo "[runtime] published: ${PUB_URL}"
fi

# --- Write manifest (always rewrite)
UPDATED_AT="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
URL="${PUB_URL:-file://${ZIP}}"

cat > "${MANIFEST_SRC}" <<JSON
{
  "schema": 1,
  "updated_at": "${UPDATED_AT}",
  "version": "${STAMP}",
  "zip": {
    "url": "${URL}",
    "sha256": "${SHA256}",
    "bytes": ${ZIP_BYTES}
  },
  "bin_path": "bin/box64"
}
JSON

# Mirror to OUTDIR for inspection/CI
cp -f "${MANIFEST_SRC}" "${MANIFEST_DST}"

# Convenience: copy to device Downloads (optional)
if [[ -d /sdcard/Download ]]; then
  cp -f "${ZIP}" "/sdcard/Download/$(basename "${ZIP}")"
  echo "[runtime] copied to /sdcard/Download/$(basename "${ZIP}")"
fi
