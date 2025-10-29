#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
for k in personal work; do
  pub="$HOME/.ssh/id_ed25519_${k}.pub"
  if [ -f "$pub" ]; then
    echo "=== $k key ==="
    cat "$pub"
    echo
  fi
done
echo "Add any above keys at https://github.com/settings/keys (or use: gh ssh-key add ...)"
