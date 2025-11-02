#!/usr/bin/env bash
set -euo pipefail
: "${SERIAL:?SERIAL not set}"
adb -s "$SERIAL" shell 'run-as com.robotforest.launcher rm -rf app_runtime/runtime app_runtime/_scratch || true'
adb -s "$SERIAL" shell pm clear com.robotforest.launcher >/dev/null
echo "[ok] runtime wiped + app data cleared"
