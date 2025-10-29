#!/data/data/com.termux/files/usr/bin/env bash
set -euo pipefail

BROKEN_TAR="/sdcard/Download/android_broken.tar.gz"
WORKING_DIR="$HOME/android/RobotForest"
OUT_DIR="$HOME/tmp/rf_broken"
REPORT="/sdcard/RobotForest/diff-report.txt"

mkdir -p "$(dirname "$REPORT")"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

#echo "[RF] Unzipping $BROKEN_TAR ..." > "$REPORT"
#tar -xzvf "$BROKEN_TAR" -d "$OUT_DIR"

echo "[RF] Broken archive tree:" >> "$REPORT"
( cd "$OUT_DIR" && find . -maxdepth 6 -print | sort ) >> "$REPORT"

# Greps for quick signals
echo -e "\n[RF] Quick signals (broken dir):" >> "$REPORT"
BROKEN_APP="$OUT_DIR/app"
grep -Rsn 'com.android.application' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn 'compileSdk' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn 'targetSdk' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn 'ndkVersion' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn 'signingConfigs' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn 'ACTION_MANAGE_OVERLAY_PERMISSION' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn 'ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn '<queries>' "$OUT_DIR" | head -n 5 >> "$REPORT" || true
grep -Rsn 'package="com.robotforest.launcher"' "$OUT_DIR" | head -n 5 >> "$REPORT" || true

# Diff core files against working dir
echo -e "\n[RF] Unified diffs (working vs broken):" >> "$REPORT"
for f in \
  settings.gradle \
  app/build.gradle \
  app/src/main/AndroidManifest.xml \
  app/src/main/cpp/CMakeLists.txt \
  app/src/main/cpp/main_android.c \
  app/src/main/res/layout/activity_main.xml \
  app/src/main/res/values/strings.xml \
  app/src/main/java/com/robotforest/launcher/MainActivity.java
do
  echo -e "\n--- DIFF: $f ---" >> "$REPORT"
  diff -ruN "$WORKING_DIR/$f" "$OUT_DIR/$f" >> "$REPORT" || true
done

# Inspect gradle.properties (broken archive)
if [ -f "$OUT_DIR/gradle.properties" ]; then
  echo -e "\n[RF] gradle.properties (broken):" >> "$REPORT"
  sed -n '1,200p' "$OUT_DIR/gradle.properties" >> "$REPORT"
fi

echo -e "\n[RF] Analysis complete. Report at: $REPORT"
echo "[RF] Tip: Share the last ~200 lines if you want me to call out exact fixes."
