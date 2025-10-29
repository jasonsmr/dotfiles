#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
LOGDIR="$HOME/logs/cross"; mkdir -p "$LOGDIR"

one() {
  local name="$1"; shift
  echo "=== RUN: $name ==="
  TRACE=1 bash -x "$@" 2>&1 | tee -a "$LOGDIR/$name-$(date +%F_%H-%M-%S).log"
}

# Always load env
. "$HOME/bin/env-cross.sh"

# Assume binutils already done; now do headers -> crt -> winpthreads -> gcc
one headers "$HOME/bin/build-mingw-headers.sh"
one crt     "$HOME/bin/build-mingw-crt.sh"
one winpth  "$HOME/bin/build-winpthread.sh"
one gcc     "$HOME/bin/build-gcc-mingw.sh"

echo "=== ALL DONE ==="
