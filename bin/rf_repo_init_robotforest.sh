#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# ===========================
# RobotForest GH bootstrapper
# ===========================

# CONFIG
REPO_DIR="$HOME/android/RobotForest"
REPO_NAME="RobotForest"
VISIBILITY="private"   # private | public | internal
DESCRIPTION="RobotForest launcher – Android NDK/Gradle app (Termux-friendly build)."
DEFAULT_BRANCH="main"
REMOTE_ALIAS="origin"
SSH_HOST_ALIAS="github-personal"   # from rf_git_bootstrap.sh

# Which key to use for commit signing (SSH-based)
PERSONAL_KEY="$HOME/.ssh/id_ed25519_personal"
PERSONAL_KEY_PUB="$HOME/.ssh/id_ed25519_personal.pub"
ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"

banner(){ printf "\n==== %s ====\n" "$*"; }
die(){ echo "ERROR: $*" >&2; exit 1; }
cmd(){ echo "+ $*"; eval "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

have git || die "Missing dependency: git"
have gh  || die "Missing dependency: gh"
have ssh-keygen || die "Missing dependency: ssh-keygen"
have ssh-agent  || die "Missing dependency: ssh-agent"
have ssh-add    || die "Missing dependency: ssh-add"

GITHUB_USER="$(gh api user --jq .login 2>/dev/null || true)"
[ -n "$GITHUB_USER" ] || die "GitHub CLI not logged in (run: gh auth login)"

# --- Ensure ssh-agent and key are loaded (for SSH commit signing and pushes) ---
banner "Ensuring ssh-agent and key are available"
if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "${SSH_AUTH_SOCK:-/dev/null}" ]; then
  eval "$(ssh-agent -s)"
fi

# Add key if not already present
if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$PERSONAL_KEY" 2>/dev/null | awk '{print $2}')" 2>/dev/null; then
  [ -f "$PERSONAL_KEY" ] || die "Missing SSH key: $PERSONAL_KEY"
  ssh-add "$PERSONAL_KEY" || die "ssh-add failed for $PERSONAL_KEY"
fi

# --- Ensure allowed signers for SSH signing ---
banner "Ensuring SSH allowed signers file"
mkdir -p "$HOME/.ssh"
touch "$ALLOWED_SIGNERS"
# Add/update a line for this key (principal 'jasonsmr')
if ! grep -qF "jasonsmr " "$ALLOWED_SIGNERS"; then
  printf "jasonsmr %s\n" "$(cat "$PERSONAL_KEY_PUB")" >> "$ALLOWED_SIGNERS"
fi
chmod 600 "$ALLOWED_SIGNERS" || true

# --- Global signing config (idempotent) ---
banner "Configuring git for SSH commit signing (idempotent)"
git config --global gpg.format ssh
git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"
git config --global user.signingkey "$PERSONAL_KEY_PUB"
git config --global commit.gpgsign true

# --- Prepare repo directory ---
banner "Preparing repository directory"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

# --- Init repo if needed ---
if [ ! -d .git ]; then
  banner "Initializing local git repo"
  git init
  git config --local init.defaultBranch "$DEFAULT_BRANCH" || true
fi

# --- Write scaffolding only if absent ---
banner "Writing repository files (created only if absent)"

if [ ! -f .gitignore ]; then
cat > .gitignore <<'EOF'
*.iml
.gradle/
.local/
.idea/
build/
captures/
.externalNativeBuild/
.cxx/
**/build/
**/.gradle/
**/.cxx/
*.apk
*.ap_
*.aab
*.aar
*.jks
*.keystore
*.keystore.properties
keystore.properties
*.pem
*.p12
*.asc
*.log
*.trace
hs_err_pid*
.DS_Store
Thumbs.db
*.swp
*.swo
.sdkman/
.android/
.cargo/
EOF
fi

if [ ! -f .gitattributes ]; then
cat > .gitattributes <<'EOF'
* text=auto eol=lf
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.mp3 binary
*.mp4 binary
*.ogg binary
*.zip binary
*.aar binary
*.aab binary
*.apk binary
*.keystore binary
*.jks binary
EOF
fi

if [ ! -f .editorconfig ]; then
cat > .editorconfig <<'EOF'
root = true
[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.{java,kt,kts,gradle,xml}]
indent_size = 4
EOF
fi

if [ ! -f README.md ]; then
cat > README.md <<EOF
# $REPO_NAME

Android launcher project built on-device in **Termux** (Z Fold 4), with NDK/Gradle.

## Build (on device)
\`\`\`bash
cd ~/android/RobotForest
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
\`\`\`

## CI
GitHub Actions workflow builds Debug APK on push/PR and uploads as artifact.
EOF
fi

mkdir -p .github/workflows
if [ ! -f .github/workflows/android.yml ]; then
cat > .github/workflows/android.yml <<'EOF'
name: Android CI (Debug)

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  build-debug:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'

      - name: Gradle cache
        uses: gradle/actions/setup-gradle@v3

      - name: Build Debug
        run: ./gradlew :app:assembleDebug --stacktrace

      - name: Upload APK
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: app-debug-apk
          path: app/build/outputs/apk/debug/*.apk
EOF
fi

# --- Stage and attempt signed commit; fallback if needed ---
banner "Staging and committing (signed if possible)"
git add -A || true

needs_commit=1
if git rev-parse --quiet --verify HEAD >/dev/null; then
  # Existing repo: only commit if staged changes
  if git diff --cached --quiet; then
    needs_commit=0
  fi
fi

if [ "$needs_commit" -eq 1 ]; then
  signed_ok=1
  if ! git commit -S -m "Initial RobotForest import: scaffolding + CI"; then
    echo "WARN: Signed commit failed (likely agent or signers issue). Falling back to unsigned…" >&2
    signed_ok=0
  fi
  if [ "$signed_ok" -eq 0 ]; then
    git commit -m "Initial RobotForest import: scaffolding + CI (unsigned)"
  fi
else
  echo "Nothing new to commit."
fi

# --- Create or reuse GitHub repo ---
banner "Ensuring GitHub repo exists"
REPO_FULL="$GITHUB_USER/$REPO_NAME"
if gh repo view "$REPO_FULL" >/dev/null 2>&1; then
  echo "Repo already exists on GitHub."
else
  gh repo create "$REPO_FULL" --"$VISIBILITY" --description "$DESCRIPTION" --disable-wiki --enable-issues
fi

SSH_URL="git@${SSH_HOST_ALIAS}:${REPO_FULL}.git"
if git remote | grep -qx "$REMOTE_ALIAS"; then
  CUR_URL="$(git remote get-url "$REMOTE_ALIAS")"
  [ "$CUR_URL" = "$SSH_URL" ] || git remote set-url "$REMOTE_ALIAS" "$SSH_URL"
else
  git remote add "$REMOTE_ALIAS" "$SSH_URL"
fi

# --- Push & set default branch ---
banner "Pushing and setting default branch"
git branch -M "$DEFAULT_BRANCH"
git push -u "$REMOTE_ALIAS" "$DEFAULT_BRANCH"

gh api -X PATCH "repos/$REPO_FULL" -f default_branch="$DEFAULT_BRANCH" >/dev/null 2>&1 || true

banner "Done!"
echo "Repo:   https://github.com/$REPO_FULL"
echo "Remote: $(git remote get-url $REMOTE_ALIAS)"
