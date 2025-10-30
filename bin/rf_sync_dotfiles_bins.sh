#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/dotfiles"
mkdir -p bin
rsync -av --delete "$HOME/bin/" ./bin/
git add -A
git commit -m "sync: bin update $(date -u +%F\ %T\Z)" || true
git push
