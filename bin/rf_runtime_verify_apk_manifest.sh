#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$PWD}"
APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"
TMP="${TMP:-$HOME/tmp}"; mkdir -p "$TMP"
MAN_DISK="$ROOT/scripts/runtime/runtime-manifest.json"
jq -cS . "$MAN_DISK" > "$TMP/_m_disk.json"
unzip -p "$APK" assets/runtime/manifest.json | jq -cS . > "$TMP/_m_apk.json"
cmp -s "$TMP/_m_disk.json" "$TMP/_m_apk.json" && echo "[OK] disk==apk" || { echo "[DIFF]"; diff -u "$TMP/_m_disk.json" "$TMP/_m_apk.json" || true; exit 1; }
URL="$(jq -r .url "$MAN_DISK")"
curl -fL --retry 3 -o "$TMP/_rt.zip" "$URL"
echo -n "APK sha256: "; jq -r .sha256 "$MAN_DISK"
echo -n "ZIP sha256: "; sha256sum "$TMP/_rt.zip" | awk '{print $1}'
