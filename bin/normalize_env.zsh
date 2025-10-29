#!/usr/bin/env zsh
set -e

print -r -- "\n==> Normalizing scripts in ~/bin and ~/etc"

BIN="$HOME/bin"
ETC="$HOME/etc"

# Gather targets, skipping backups and VCS dirs
typeset -a targets
while IFS= read -r -d '' f; do
  [[ "$f" == *.bak.* ]] && continue
  [[ "$f" == */.git/* ]] && continue
  targets+=("$f")
done < <(find "$BIN" "$ETC" -type f -print0 2>/dev/null)

for f in "${targets[@]}"; do
  # Skip binaries (best-effort)
  file -b -- "$f" 2>/dev/null | grep -qiE 'text|script|shell|zsh|bash|python|perl' || continue

  # Backup
  cp -fp -- "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || cp -p -- "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)"

  # 1) Ensure TMP prelude after shebang if missing
  perl -0777 -i -pe '
    if ($. == 0) { } # quiet perl -0777
    my $wanted = q{  : ${TMP:="$HOME$TMP"}; mkdir -p -- "$TMP"};
    unless (m/^\s*:\s*\${TMP:=/m) {
      s/\A(#![^\n]*\n)/$1$wanted\n/s or
      s/\A/$wanted\n/s;
    }
  ' -- "$f"

  perl -0777 -i -pe '
  ' -- "$f"

  # 3) Normalize TMP/TMPDIR weird defaults to $HOME/tmp
  perl -0777 -i -pe '
    s{\$?HOME_DIR/?data/data/com\.termux/files/home$TMP}{\$HOME$TMP}g;
    s{\$?HOME/?data/data/com\.termux/files/home$TMP}{\$HOME$TMP}g;
    s{/data/data/com\.termux/files/(usr|home)$TMP}{\$HOME$TMP}g;
    s/TMPDIR=["'\''"]?\$\{?TMPDIR:-\$\{?TMP:[^}"'\''"]+}?["'\''"]?/TMPDIR="${TMPDIR:-${TMP:-$HOME$TMP}}"/g;
    s/TMPDIR=["'\''"]?\$\{?TMPDIR:[^}"'\''"]+}?["'\''"]?/TMPDIR="${TMPDIR:-${TMP:-$HOME$TMP}}"/g;
    s/\$\{TMP:=\/data\/data\/com\.termux\/files\/home\/data\/data\/com\.termux\/files\/home\$TMP\}/\${TMP:=$HOME\$TMP}/g;
    s/\$\{TMP:="?\$HOME\/data\/data\/com\.termux\/files\/home\$TMP"?\}/\${TMP:=$HOME\$TMP}/g;
  ' -- "$f"

  # 4) Replace /tmp with $TMP only in non-comment code lines
  perl -0777 -i -pe '
    s{(^[^\n#]*?)$TMP}{$1\$TMP}mg;
  ' -- "$f"

  # 5) Pulse socket paths to $TMP (Wine/Steam helpers)
  perl -0777 -i -pe '
    s{unix:\$PREFIX/(?:data/data/com\.termux/files/)?tmp/}{unix:$TMP/}g;
  ' -- "$f"
done

print -r -- "==> Re-auditing…"
print -r -- "==> Done."
