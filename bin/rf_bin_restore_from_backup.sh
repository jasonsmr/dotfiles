#!/data/data/com.termux/files/usr/bin/bash
# Interactively restore files from ~/dotfiles/bin/bin to ~/bin.
# Makes per-file safety backups in ~/bin/.pre-restore-<timestamp>/ before overwriting.

PRIMARY="$HOME/bin"
BACKUP="$HOME/dotfiles/bin/bin"
TS="$(date +%Y%m%d-%H%M%S)"
SAFEDIR="$PRIMARY/.pre-restore-$TS"

[ -n "$1" ] && PRIMARY="$1"
[ -n "$2" ] && BACKUP="$2"

echo "== rf_bin_restore_from_backup =="
echo "primary:  $PRIMARY"
echo "backup:   $BACKUP"
echo "safedir:  $SAFEDIR"
echo

mkdir -p "$SAFEDIR" 2>/dev/null

# Build lists
list_rel() { (cd "$1" 2>/dev/null && find . -mindepth 1 -type f -o -type l | sed 's#^\./##' | LC_ALL=C sort); }
primary_list="$(list_rel "$PRIMARY")"
backup_list="$(list_rel "$BACKUP")"

# Choose mode
echo "Choose restore mode:"
echo "  1) Restore ALL files from backup to primary"
echo "  2) Restore ONLY missing or changed files"
echo "  3) Pick files interactively (fuzzy contains match)"
read -r -p "[1/2/3]: " mode

restore_one() {
  rel="$1"
  src="$BACKUP/$rel"
  dst="$PRIMARY/$rel"
  dstdir="$(dirname "$dst")"
  [ -e "$src" ] || { echo "  [skip] missing in backup: $rel"; return; }
  mkdir -p "$dstdir" 2>/dev/null
  if [ -e "$dst" ]; then
    mkdir -p "$SAFEDIR/$(dirname "$rel")" 2>/dev/null
    cp -af "$dst" "$SAFEDIR/$rel"
    echo "  [save] $rel -> $SAFEDIR/$rel"
  fi
  cp -af "$src" "$dst"
  echo "  [restored] $rel"
}

if [ "$mode" = "1" ]; then
  echo "[mode] full restore"
  printf "%s\n" $backup_list | while read -r rel; do
    restore_one "$rel"
  done

elif [ "$mode" = "2" ]; then
  echo "[mode] missing/changed"
  # Compute missing/changed
  comm_wrap() {
    printf "%s\n" "$1" > /tmp/rf_p.$$
    printf "%s\n" "$2" > /tmp/rf_b.$$
    comm /tmp/rf_p.$$ /tmp/rf_b.$$
    rm -f /tmp/rf_p.$$ /tmp/rf_b.$$
  }
  only_p=$(comm_wrap "$primary_list" "$backup_list" | awk 'NR==1{print}')
  only_b=$(comm_wrap "$primary_list" "$backup_list" | awk 'NR==2{print}')
  both=$(comm_wrap "$primary_list" "$backup_list" | awk 'NR==3{print}')

  # changed = hashes differ
  changed=""
  printf "%s\n" $both | while read -r rel; do
    [ -z "$rel" ] && continue
    hp=$(sha256sum "$PRIMARY/$rel" 2>/dev/null | awk '{print $1}')
    hb=$(sha256sum "$BACKUP/$rel"  2>/dev/null | awk '{print $1}')
    if [ "$hp" != "$hb" ]; then
      echo "$rel"
    fi
  done > /tmp/rf_changed.$$

  changed="$(cat /tmp/rf_changed.$$)"
  rm -f /tmp/rf_changed.$$

  echo "[restore] missing in primary:"
  printf "  %s\n" $only_b
  echo "[restore] changed files:"
  printf "  %s\n" $changed

  printf "%s\n" $only_b $changed | sed '/^$/d' | while read -r rel; do
    restore_one "$rel"
  done

else
  echo "[mode] interactive"
  while :; do
    read -r -p "type a substring to match (empty to quit): " q
    [ -z "$q" ] && break
    matches=$(printf "%s\n" $backup_list | grep -i -- "$q")
    if [ -z "$matches" ]; then
      echo "  no matches."
      continue
    fi
    echo "Matches:"
    nl -ba <<< "$matches"
    read -r -p "enter numbers to restore (e.g. 1 3 5), or 'a' for all matches: " sel
    if [ "$sel" = "a" ]; then
      printf "%s\n" $matches | while read -r rel; do restore_one "$rel"; done
    else
      for n in $sel; do
        rel=$(printf "%s\n" $matches | sed -n "${n}p")
        [ -n "$rel" ] && restore_one "$rel"
      done
    fi
  done
fi

echo
echo "[done] Safeties stored under: $SAFEDIR"
exit 0
