#!/usr/bin/env zsh
# ---- toolchain/termux prelude ----
if [ -z "$__TOOLCHAIN_PRELUDE" ]; then
  __TOOLCHAIN_PRELUDE=1
  : ${TMP:="$HOME$TMP"}; mkdir -p -- "$TMP"
  # minimal PATH glue (keep short, user can extend in ~/.zshrc)
  if [ -d "$HOME/opt/toolchain/aarch64-linux-android/bin" ]; then
    case ":$PATH:" in *":$HOME/opt/toolchain/aarch64-linux-android/bin:"*) ;; 
      *) PATH="$HOME/opt/toolchain/aarch64-linux-android/bin:$PATH";;
    esac
  fi
fi
# ---- end prelude ----


log(){ print -r -- "\n==> $*"; }
mv_safe(){ src="$1"; dst="$2"; [ -e "$src" ] || return 0; print -r -- "+ mv -- $src -> $dst"; mv -- "$src" "$dst"; }

BIN="$HOME/bin"
ETC="$HOME/etc"
ARCH="$HOME/archive_home_cleanup"

mkdir -p -- "$BIN" "$ETC" "$ARCH"

log "Moving known toolchain/IDE scripts to ~/bin:"
for s in \
  "$HOME/clion-env.sh" "$HOME/clion-start" "$HOME/clion-termux" \
  "$HOME/compile-env.sh" "$HOME/env-sane.sh" \
  "$HOME/rebuild-bin.sh" "$HOME/rebuild_stage1_verbose.sh" \
  "$HOME/fix_stage1.sh" "$HOME/patch_stage1_ldpath.sh" \
  "$HOME/build_gcc.sh" \
  "$HOME/first_error_from_ninja.sh" \
  "$HOME/check_libcody_after_fix.sh" \
  "$HOME/verify_fizban_env.sh" \
  "$HOME/meson_build_toolchains.sh" \
  ; do
  [ -e "$s" ] && mv_safe "$s" "$BIN/"
done

log "Moving config/helper headers to ~/etc (if present):"
for s in \
  "$HOME/android-compat.h" "$HOME/gcc-cxx-compat.h" "$HOME/gcc-shims" \
  ; do
  [ -e "$s" ] && mv_safe "$s" "$ETC/"
done

# Things likely not needed in $HOME root; archive them non-destructively
log "Archiving misc one-off files from \$HOME to ~/archive_home_cleanup:"
for s in \
  "$HOME/Makefile" "$HOME/config.log" "$HOME/termux_packages.list" "$HOME/termux_packages.list.bak."* \
  "$HOME/termux-desktop.log" "$HOME/texlive-suite-check.sh" \
  "$HOME/t.c" "$HOME/deleteme.txt" "$HOME/toolchain-env-pack.zip" \
  "$HOME/startxfce_termux.sh" "$HOME/startxfce4_termux.sh" \
  "$HOME/termux-gui.sh" "$HOME/termux-gui.sh.back" "$HOME/termux-gui.sh~" \
  ; do
  for f in $~s; do
    [ -e "$f" ] && mv_safe "$f" "$ARCH/"
  done
done

log "Done. Review $ARCH and prune at will."
