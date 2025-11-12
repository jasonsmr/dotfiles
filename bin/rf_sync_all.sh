#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
sync_one() { cd "$1"; git add -A; git commit -m "chore(sync)" || true; git push -u origin "$2"; }
sync_one "$HOME/android/RobotForest" "robotforest-wow64-runtime"
sync_one "$HOME/android/robotforest-wow64-runtime" "ci/productionize"
sync_one "$HOME/dotfiles" "main"
echo "All pushed."
