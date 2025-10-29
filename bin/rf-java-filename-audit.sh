#!/system/bin/sh
set -eu

ROOT="$HOME/android/RobotForest/app/src/main/java"

find "$ROOT" -type f -name '*.java' | while read -r f; do
  base="$(basename "$f" .java)"
  # Grep first public type declaration (class|interface|enum|record)
  tname="$(sed -n 's/^[[:space:]]*public[[:space:]]\+\(final[[:space:]]\+\)\?\(class\|interface\|enum\|record\)[[:space:]]\+\([A-Za-z0-9_]\+\).*/\3/p' "$f" | head -n1 || true)"
  [ -z "${tname:-}" ] && continue
  if [ "$tname" != "$base" ]; then
    echo "[mismatch] $f  -> public $tname   (file is $base.java)"
  fi
done
