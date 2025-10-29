#!/system/bin/sh
set -eu
GRADLE_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
SDK_AAPT2="${1:-$HOME/opt/android-sdk/build-tools/34.0.4/aapt2}"

count=0
find "$GRADLE_HOME/caches" -type f -name aapt2 2>/dev/null | while read -r f; do
  count=$((count+1))
  if file "$f" | grep -q "x86-64"; then
    echo "[WARN] x86-64 aapt2 found: $f"
  elif ! head -c4 "$f" | od -An -tx1 | grep -q "7f 45 4c 46"; then
    echo "[WARN] non-ELF aapt2 wrapper/script: $f"
  else
    # Try to see if it’s our shim (has our section) or the SDK binary (size/hash check)
    sz_fs=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
    sz_sd=$(stat -c%s "$SDK_AAPT2" 2>/dev/null || stat -f%z "$SDK_AAPT2")
    if [ "$sz_fs" = "$sz_sd" ]; then
      echo "[OK] SDK aapt2 in cache: $f"
    else
      echo "[OK] shim aapt2 present: $f (size differs from SDK binary)"
    fi
  fi
done

[ "$count" -gt 0 ] || echo "[INFO] No cached aapt2 files yet."
