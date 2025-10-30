#!/data/data/com.termux/files/usr/bin/bash
# Compares ~/bin against ~/dotfiles/bin/bin and reports:
# - files missing in backup or primary
# - content differences via sha256
# - symlink target differences
# - executability & shebang sanity
# Never exits non-zero.

PRIMARY="$HOME/bin"
BACKUP="$HOME/dotfiles/bin/bin"

# allow overrides
[ -n "$1" ] && PRIMARY="$1"
[ -n "$2" ] && BACKUP="$2"

ts() { date +"%Y-%m-%d %H:%M:%S"; }

echo "== rf_bin_integrity_check =="
echo "time:     $(ts)"
echo "primary:  $PRIMARY"
echo "backup:   $BACKUP"
echo

errors=0

if [ ! -d "$PRIMARY" ]; then
  echo "[WARN] primary dir missing: $PRIMARY"
  errors=$((errors+1))
fi
if [ ! -d "$BACKUP" ]; then
  echo "[WARN] backup dir missing: $BACKUP"
  errors=$((errors+1))
fi

# Safe find wrapper (no -print0 needed; paths should be simple under ~/bin)
list_rel() {
  local root="$1"
  (cd "$root" 2>/dev/null && find . -mindepth 1 -type f -o -type l | sed 's#^\./##' | LC_ALL=C sort)
}

# Build lists
primary_list="$(list_rel "$PRIMARY")"
backup_list="$(list_rel "$BACKUP")"

# Quick counts
pcount=$(printf "%s\n" "$primary_list" | wc -l | tr -d ' ')
bcount=$(printf "%s\n" "$backup_list"  | wc -l | tr -d ' ')
echo "[info] primary files: $pcount"
echo "[info] backup  files: $bcount"
echo

# Set arithmetic to avoid empty set complaints
comm_wrap() {
  # prints lines present only in set1, only in set2, and common
  # usage: comm_wrap "$list1" "$list2"
  # requires both sorted
  printf "%s\n" "$1" > /tmp/rf_p.$$
  printf "%s\n" "$2" > /tmp/rf_b.$$
  comm /tmp/rf_p.$$ /tmp/rf_b.$$
  rm -f /tmp/rf_p.$$ /tmp/rf_b.$$
}

only_p=$(comm_wrap "$primary_list" "$backup_list" | awk 'NR==1{print}')
only_b=$(comm_wrap "$primary_list" "$backup_list" | awk 'NR==2{print}')
both=$(comm_wrap "$primary_list" "$backup_list" | awk 'NR==3{print}')

if [ -n "$only_p" ]; then
  echo "[MISS-BACKUP] present in PRIMARY, missing in BACKUP:"
  printf "  %s\n" $only_p
  echo
fi

if [ -n "$only_b" ]; then
  echo "[EXTRA-BACKUP] present in BACKUP, missing in PRIMARY:"
  printf "  %s\n" $only_b
  echo
fi

# For files present in both, compare contents and metadata
differences=0
bad_exec=0
bad_shebang=0
link_diffs=0

echo "[scan] comparing common files…"

# util: detect ELF
is_elf() {
  local f="$1"
  head -c4 "$f" 2>/dev/null | od -An -tx1 -N4 2>/dev/null | grep -qi "7f 45 4c 46"
}

# util: has shebang
has_shebang() {
  local f="$1"
  head -n1 "$f" 2>/dev/null | grep -q "^#!"
}

# util: sha256
h() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# Iterate over common paths
printf "%s\n" $both | while read -r rel; do
  [ -z "$rel" ] && continue
  p="$PRIMARY/$rel"
  b="$BACKUP/$rel"

  # Symlink handling
  if [ -L "$p" ] || [ -L "$b" ]; then
    tp="$(readlink "$p" 2>/dev/null || echo "<notlink>")"
    tb="$(readlink "$b" 2>/dev/null || echo "<notlink>")"
    if [ "$tp" != "$tb" ]; then
      echo "[LINK-DIFF] $rel"
      echo "   primary -> $tp"
      echo "   backup  -> $tb"
      link_diffs=$((link_diffs+1))
    fi
    # also compare dereferenced content if both resolve to files
    if [ ! -L "$p" ] && [ ! -L "$b" ]; then
      : # nothing extra
    fi
  fi

  if [ -f "$p" ] && [ -f "$b" ]; then
    hp=$(h "$p")
    hb=$(h "$b")
    if [ "$hp" != "$hb" ]; then
      echo "[DIFF] $rel (content hash differs)"
      differences=$((differences+1))
    fi

    # Executable sanity: if it looks like script (shebang) or ELF, it SHOULD be +x
    needs_exec=0
    if has_shebang "$p"; then needs_exec=1; fi
    if is_elf "$p"; then needs_exec=1; fi

    if [ "$needs_exec" = 1 ]; then
      if [ ! -x "$p" ]; then
        echo "[EXEC-FLAG] primary not executable: $rel"
        bad_exec=$((bad_exec+1))
      fi
      if [ ! -x "$b" ]; then
        echo "[EXEC-FLAG] backup not executable:  $rel"
        bad_exec=$((bad_exec+1))
      fi
    fi

    # Shebang sanity for scripts
    if has_shebang "$p"; then
      sb=$(head -n1 "$p" | sed 's/[\r\n]//g')
      case "$sb" in
        "#!/system/bin/sh"|\
        "#!/data/data/com.termux/files/usr/bin/bash"|\
        "#!/data/data/com.termux/files/usr/bin/env bash"|\
        "#!/data/data/com.termux/files/usr/bin/zsh"|\
        "#!/data/data/com.termux/files/usr/bin/env zsh")
          : ;; # OK
        *)
          echo "[SHEBANG] $rel -> $sb"
          bad_shebang=$((bad_shebang+1))
          ;;
      esac
    fi
  fi
done

echo
echo "== Summary =="
printf "missing in backup : %s\n" "$(printf "%s\n" "$only_p" | sed '/^$/d' | wc -l | tr -d ' ')"
printf "extra in backup   : %s\n" "$(printf "%s\n" "$only_b" | sed '/^$/d' | wc -l | tr -d ' ')"
printf "content diffs     : %s\n" "$differences"
printf "symlink diffs     : %s\n" "$link_diffs"
printf "exec-bit issues   : %s\n" "$bad_exec"
printf "shebang warnings  : %s\n" "$bad_shebang"
echo
echo "[done] If anything above is non-zero, use rf_bin_restore_from_backup.sh to restore selectively."
exit 0
