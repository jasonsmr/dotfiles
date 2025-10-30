#!/data/data/com.termux/files/usr/bin/bash
# Simple/robust – avoids strict flags to prevent terminal kills

ts="$(date +%Y%m%d-%H%M)"
rf_repo="$HOME/android/RobotForest"
df_repo="$HOME/dotfiles"
dl_dir="/sdcard/Download"
snap_name="RobotForest-snap-${ts}.tar.gz"
tag="snapshot-${ts}"

echo "[backup] pushing dotfiles..."
git -C "$df_repo" add -A && git -C "$df_repo" commit -m "dotfiles snapshot $ts" || true
git -C "$df_repo" push || true

echo "[backup] pushing RobotForest..."
git -C "$rf_repo" add -A && git -C "$rf_repo" commit -m "RobotForest snapshot $ts" || true
git -C "$rf_repo" push || true

echo "[backup] tag RobotForest: $tag"
git -C "$rf_repo" tag -f "$tag" || true
git -C "$rf_repo" push -f origin "refs/tags/$tag" || true

echo "[backup] local trimmed tar to $dl_dir/$snap_name"
(
  cd "$rf_repo" || exit 0
  tar --exclude='./.git' \
      --exclude='./**/build' \
      --exclude='./**/.cxx' \
      --exclude='./**/.externalNativeBuild' \
      -czf "$dl_dir/$snap_name" .
) || true

apk="$rf_repo/app/build/outputs/apk/debug/app-debug.apk"
if [ -f "$apk" ]; then
  echo "[backup] make checksums for APK"
  ( cd "$(dirname "$apk")" && sha256sum app-debug.apk > app-debug.apk.sha256 ) || true
fi

echo "[backup] create draft GitHub Release w/ artifacts (if gh is logged-in)"
repo_slug="jasonsmr/RobotForest"

# Create or update a draft release
if gh release view "$tag" -R "$repo_slug" >/dev/null 2>&1; then
  echo "[backup] updating existing release $tag"
else
  gh release create "$tag" --draft -t "$tag" -n "Automated snapshot $ts" -R "$repo_slug" || true
fi

# Attach artifacts if present
[ -f "$apk" ] && gh release upload "$tag" "$apk" -R "$repo_slug" --clobber || true
[ -f "$rf_repo/app/build/outputs/apk/debug/app-debug.apk.sha256" ] && \
  gh release upload "$tag" "$rf_repo/app/build/outputs/apk/debug/app-debug.apk.sha256" -R "$repo_slug" --clobber || true

echo "[backup] done."
