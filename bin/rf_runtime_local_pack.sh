#!/usr/bin/env bash

# --- Config: point this to your built box64 binary (ELF for aarch64)
: "${BOX64_SRC:=$HOME/opt/box64/bin/box64}"   # change if different
OUTDIR="${PWD}/out/runtime"
STAMP="$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short=12 HEAD || echo manual)"
ZIP="${OUTDIR}/runtime-${STAMP}.zip"
STAGE="${PWD}/scripts/runtime/runtime_staging"
MANIFEST_SRC="${PWD}/scripts/runtime/runtime-manifest.json"
MANIFEST_DST="${OUTDIR}/runtime-manifest.json"

mkdir -p "${OUTDIR}" "${STAGE}/bin"

# 1) Stage files
cp -f "${MANIFEST_SRC}" "${MANIFEST_DST}"

# 2) Sanity: box64 must exist and be ELF
if [[ ! -f "${BOX64_SRC}" ]]; then
  echo "ERROR: BOX64_SRC not found: ${BOX64_SRC}" >&2
  exit 1
fi

head -c 4 "${BOX64_SRC}" | hexdump -C | grep -q '7f 45 4c 46' || {
  echo "ERROR: ${BOX64_SRC} is not an ELF binary (missing 0x7F 'ELF' magic)" >&2
  file "${BOX64_SRC}" || true
  exit 1
}

# 3) Copy the real ELF into staging
install -m 0755 "${BOX64_SRC}" "${STAGE}/bin/box64"

# (Optional: add other payload files under ${STAGE})

# 4) Create ZIP (deterministic-ish)
(
  cd "${STAGE}"
  # store paths without leading './'
  find . -type f -print0 | sort -z | xargs -0 zip -9 -X -r "${ZIP}" >/dev/null
)

# 5) Print/verify
echo "[runtime] staging: ${STAGE}"
echo "[runtime] out zip: ${ZIP}"
echo "[runtime] checking ELF in zip..."
unzip -p "${ZIP}" bin/box64 | head -c 4 | hexdump -C

# 6) SHA256 + publish if GH_PUBLISH=1
sha256sum "${ZIP}" | awk '{print $1}' > "${ZIP}.sha256"
echo "[runtime] sha256: $(cat "${ZIP}.sha256")"

if [[ "${GH_PUBLISH:-}" == "1" ]]; then
  gh release upload auto "${ZIP}" "${ZIP}.sha256" --clobber
  echo "[runtime] published: https://github.com/jasonsmr/RobotForest/releases/download/auto/$(basename "${ZIP}")"
  echo "[runtime] published sha: https://github.com/jasonsmr/RobotForest/releases/download/auto/$(basename "${ZIP}.sha256")"
fi

# 7) Copy to device download folder for easy side-loading if desired
if [[ -d /sdcard/Download ]]; then
  cp -f "${ZIP}" "/sdcard/Download/$(basename "${ZIP}")"
  echo "[runtime] copied to /sdcard/Download/$(basename "${ZIP}")"
fi
