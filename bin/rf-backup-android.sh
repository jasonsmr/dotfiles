#!/data/data/com.termux/files/usr/bin/env bash
set -euo pipefail
ts="$(date +%Y%m%d_%H%M%S)"

# 1) Project essentials
tar --exclude-vcs -czf "/sdcard/Download/robotforest_proj_${ts}.tar.gz" \
  -C "$HOME/android" \
  RobotForest/gradle.properties \
  RobotForest/build.gradle \
  RobotForest/settings.gradle \
  RobotForest/gradle \
  RobotForest/gradlew \
  RobotForest/gradlew.bat \
  RobotForest/app/build.gradle \
  RobotForest/app/src

# 2) Global guardrails (gradle init, sdk aapt2, shim source+binary)
tar -czf "/sdcard/Download/robotforest_guard_${ts}.tar.gz" \
  "$HOME/.gradle/init.d/10-aapt2-wrapper.gradle" \
  "$HOME/opt/android-sdk/build-tools/34.0.4/aapt2" \
  "$HOME/src/rf_aapt2_shim.c" \
  "$HOME/bin/rf-aapt2"

echo "Backups written:"
echo "  /sdcard/Download/robotforest_proj_${ts}.tar.gz"
echo "  /sdcard/Download/robotforest_guard_${ts}.tar.gz"
