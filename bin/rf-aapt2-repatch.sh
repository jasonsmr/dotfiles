#!/system/bin/sh
set -eu
GRADLE_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
REAL="${1:-$HOME/opt/android-sdk/build-tools/34.0.4/aapt2}"

[ -x "$REAL" ] || { echo "SDK aapt2 not found/executable: $REAL" >&2; exit 1; }

repl=0
find "$GRADLE_HOME/caches" -type f -name aapt2 2>/dev/null | while read -r f; do
  chmod u+rw "$f" 2>/dev/null || true
  cp -f "$REAL" "$f"
  chmod 755 "$f"
  echo "[patched] $f"
  repl=$((repl+1))
done

[ "$repl" -gt 0 ] || echo "[info] no cache entries patched."
