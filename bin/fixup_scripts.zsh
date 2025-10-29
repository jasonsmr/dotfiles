#!/usr/bin/env zsh

PRELUDE=$'# ---- toolchain/termux prelude ----\n'\
$'if [ -z "$__TOOLCHAIN_PRELUDE" ]; then\n'\
$'  __TOOLCHAIN_PRELUDE=1\n'\
$'  : ${TMP:="$HOME$TMP"}; mkdir -p -- "$TMP"\n'\
$'  # minimal PATH glue (keep short, user can extend in ~/.zshrc)\n'\
$'  if [ -d "$HOME/opt/toolchain/aarch64-linux-android/bin" ]; then\n'\
$'    case ":$PATH:" in *":$HOME/opt/toolchain/aarch64-linux-android/bin:"*) ;; \n'\
$'      *) PATH="$HOME/opt/toolchain/aarch64-linux-android/bin:$PATH";;\n'\
$'    esac\n'\
$'  fi\n'\
$'fi\n'\
$'# ---- end prelude ----\n'

ts() { print -r -- "$(date +%Y%m%d-%H%M%S)"; }

backup_and_edit() {
  local f="$1" stamp="$(ts)"
  [ -f "$f" ] || return 0
  cp -p -- "$f" "$f.bak.$stamp" || return 0


  # Swap /tmp with $TMP where it’s obvious (not in comments)
  perl -0777 -pe 's{(^[^\n#]*)($TMP)}{$1$ENV{TMP}}mg' -i -- "$f"

  # Ensure we have the prelude near top (after shebang if present)
  if ! grep -q '__TOOLCHAIN_PRELUDE' "$f"; then
    if head -1 "$f" | grep -q '^#!'; then
      awk 'NR==1{print; next} NR==2{print PRELUDE; next} {print}' PRELUDE="$PRELUDE" "$f" > "$f.new" \
        && mv -- "$f.new" "$f"
    else
      { printf "%s" "$PRELUDE"; cat -- "$f"; } > "$f.new" && mv -- "$f.new" "$f"
    fi
  fi

  chmod +x -- "$f" 2>/dev/null || true
  print -r -- "+ fixed: $f   (backup: $f.bak.$stamp)"
}

for f in "$HOME/bin/"*; do
  [ -f "$f" ] && backup_and_edit "$f"
done
print -r -- "Done."
