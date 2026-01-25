#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

sync_one() {
  local dir="$1"
  cd "$dir"

  echo "[sync] $(pwd)"
  git add -A
  git commit -m "chore(sync)" || true

  # push the currently checked-out branch
  git push -u origin HEAD
}

sync_one "$HOME/fizban"
sync_one "$HOME/android/RobotForest"
sync_one "$HOME/android/robotforest-wow64-runtime"
sync_one "$HOME/dotfiles"

echo "All pushed."

