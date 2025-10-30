#!/data/data/com.termux/files/usr/bin/bash
set +e
echo "[bin-sanity] comparing ~/bin vs ~/dotfiles/bin (names only)"
comm -3 <(cd "$HOME/bin" && ls -1A | sort) <(cd "$HOME/dotfiles/bin" && ls -1A | sort) | sed 's/^/\t/'
echo "[bin-sanity] if differences exist, run: dotpush"
