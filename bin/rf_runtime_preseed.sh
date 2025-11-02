#!/usr/bin/env bash
set -euo pipefail
: "${SERIAL:?SERIAL not set}"
ZIP="${1:?usage: rf_runtime_preseed.sh /path/to/runtime-*.zip}"
# sanity
head -c 4 "$ZIP" | od -An -tx1 | tr -d ' \n' | grep -q '^504b0304$' || { echo "not a zip"; exit 1; }
# stream into sandbox & unpack
adb -s "$SERIAL" shell 'run-as com.robotforest.launcher sh -lc "
  rm -rf app_runtime/runtime app_runtime/_scratch &&
  mkdir -p app_runtime/_scratch app_runtime/runtime
"'
cat "$ZIP" | adb -s "$SERIAL" shell 'run-as com.robotforest.launcher sh -lc "
  cat > app_runtime/_scratch/rt.zip &&
  unzip -o app_runtime/_scratch/rt.zip -d app_runtime/runtime >/dev/null &&
  chmod -R 0755 app_runtime/runtime/bin 2>/dev/null || true &&
  ls -l app_runtime/runtime/bin ; wc -c < app_runtime/runtime/bin/box64 ;
  dd if=app_runtime/runtime/bin/box64 bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d \" \n\"
"'
echo
echo "[ok] preseed complete"
