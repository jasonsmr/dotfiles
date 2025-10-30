#!/usr/bin/env bash
set -euo pipefail

# --- Config: where your built box64 ELF lives
: "${BOX64_SRC:=$HOME/opt/box64/bin/box64}"   # adjust if different

# Toggle: force using a local file:// URL in the manifest even if GH_PUBLISH=1
: "${FORCE_FILE_URL:=0}"

ROOT="${PWD}"
OUTDIR="${ROOT}/out/runtime"
STAGE="${ROOT}/scripts/runtime/runtime_staging"
MANIFEST_SRC="${ROOT}/scripts/runtime/runtime-manifest.json"   # embedded into APK
MANIFEST_DST="${OUTDIR}/runtime-manifest.json"                 # for CI/inspection

STAMP="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short=12 HEAD || echo manual)"
ZIP="${OUTDIR}/runtime-${STAMP}.zip"
SHA="${ZIP}.sha256"

# Clean staging to prevent lingering 22-byte stubs
rm -rf "${STAGE}"
mkdir -p "${OUTDIR}" "${STAGE}/bin"

# --- Sanity on source ELF
if [[ ! -f "${BOX64_SRC}" ]]; then
  echo "ERROR: BOX64_SRC not found: ${BOX64_SRC}" >&2
  exit 1
fi

# Magic check
if ! head -c 4 "${BOX64_SRC}" | hexdump -C | grep -q '7f 45 4c 46'; then
  echo "ERROR: ${BOX64_SRC} is not an ELF (missing 0x7F 'ELF' magic)" >&2
  file "${BOX64_SRC}" || true
  exit 1
fi

# Size guard (catch stubs like 'echo' files)
BYTES_SRC=$(stat -c%s "${BOX64_SRC}")
if (( BYTES_SRC < 1000000 )); then
  echo "ERROR: ${BOX64_SRC} too small (${BYTES_SRC} bytes) — expected a real build" >&2
  exit 1
fi

# Stage payload
install -m 0755 "${BOX64_SRC}" "${STAGE}/bin/box64"

# Create ZIP (deterministic-ish)
(
  cd "${STAGE}"
  find . -type f -print0 | sort -z | xargs -0 zip -9 -X -r "${ZIP}" >/dev/null
)

# Verify ZIP actually contains an ELF at bin/box64
echo "[runtime] staging: ${STAGE}"
echo "[runtime] out zip: ${ZIP}"
echo "[runtime] checking ELF in zip..."
if ! unzip -p "${ZIP}" bin/box64 | head -c 4 | hexdump -C | grep -q '7f 45 4c 46'; then
  echo "ERROR: ZIP does not contain a valid ELF at bin/box64" >&2
  exit 1
fi

# Hash + size
SHA256="$(sha256sum "${ZIP}" | awk '{print $1}')"
echo "${SHA256}  $(basename "${ZIP}")" > "${SHA}"
ZIP_BYTES=$(stat -c%s "${ZIP}")
echo "[runtime] sha256: ${SHA256}"

# Optionally publish
PUB_URL=""
if [[ "${GH_PUBLISH:-}" == "1" && "${FORCE_FILE_URL}" != "1" ]]; then
  # Try to infer owner/repo; fall back to RobotForest
  if gh repo view --json nameWithOwner >/dev/null 2>&1; then
    NWO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  else
    NWO="jasonsmr/RobotForest"
  fi
  # Upload assets (both zip and sha)
  gh release upload auto "${ZIP}" --clobber >/dev/null
  gh release upload auto "${SHA}" --clobber >/dev/null || true
  PUB_URL="https://github.com/${NWO}/releases/download/auto/$(basename "${ZIP}")"
  echo "[runtime] published: ${PUB_URL}"
fi

# Write manifest (this is what the app uses to fetch the runtime zip)
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

# Convenience: copy to device Downloads
if [[ -d /sdcard/Download ]]; then
  cp -f "${ZIP}" "/sdcard/Download/$(basename "${ZIP}")"
  echo "[runtime] copied to /sdcard/Download/$(basename "${ZIP}")"
fi
