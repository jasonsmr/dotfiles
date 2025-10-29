#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# --------- Configurable defaults (you can also just answer prompts) ----------
DEFAULT_NAME_PERSONAL="jasonsmr"
DEFAULT_EMAIL_PERSONAL="jasonsmr@stollc.com"           # e.g. 12345678+you@users.noreply.github.com
DEFAULT_NAME_WORK="ruprighj"
DEFAULT_EMAIL_WORK="ruprighj@mail.gvsu.edu"               # e.g. 87654321+you@users.noreply.github.com
DEFAULT_GIT_EDITOR="vim"            # or "nano"
DEFAULT_MAIN_BRANCH="main"
# ---------------------------------------------------------------------------

banner() { printf "\n==== %s ====\n" "$*"; }
ask() {
  local var="$1" prompt="$2" def="${3:-}"
  local val
  read -r -p "$prompt ${def:+[$def]}: " val || true
  if [ -z "${val:-}" ] && [ -n "$def" ]; then val="$def"; fi
  eval "$var=\"\$val\""
}

ts() { date +%Y%m%d-%H%M%S; }

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }

# --- Preflight
require git
require ssh-keygen
mkdir -p "$HOME/bin" "$HOME/.ssh" "$HOME/.config/git" "$HOME/.local/share/rf"

banner "User identities (personal/work)"
ask NAME_PERSONAL  "Personal display name"                     "$DEFAULT_NAME_PERSONAL"
ask EMAIL_PERSONAL "Personal email (GitHub noreply preferred)" "$DEFAULT_EMAIL_PERSONAL"
ask NAME_WORK      "Work display name (optional)"              "$DEFAULT_NAME_WORK"
ask EMAIL_WORK     "Work email (noreply or corp, optional)"    "$DEFAULT_EMAIL_WORK"

banner "Global defaults"
ask GIT_EDITOR     "Preferred editor"                          "$DEFAULT_GIT_EDITOR"
ask MAIN_BRANCH    "Default initial branch"                    "$DEFAULT_MAIN_BRANCH"

banner "Create SSH keys for each identity"
read -r -p "Generate PERSONAL key now? [Y/n]: " yn || true
yn=${yn:-Y}
if [[ "$yn" =~ ^[Yy]$ ]]; then
  ssh-keygen -t ed25519 -C "$EMAIL_PERSONAL" -f "$HOME/.ssh/id_ed25519_personal" -N ""
fi
read -r -p "Generate WORK key now? [y/N]: " yn || true
if [[ "$yn" =~ ^[Yy]$ ]]; then
  ssh-keygen -t ed25519 -C "${EMAIL_WORK:-$EMAIL_PERSONAL}" -f "$HOME/.ssh/id_ed25519_work" -N ""
fi

# --- SSH config with host aliases (matches the reddit guidance on separate hosts)
#     Source: r/developersIndia post recommends Host aliases & includeIf; we’re automating that.
SSHCFG="$HOME/.ssh/config"
if ! grep -q "Host github-personal" "$SSHCFG" 2>/dev/null; then
  banner "Writing ~/.ssh/config host aliases"
  {
    echo "# GitHub identity splits"
    echo "Host github-personal"
    echo "  HostName github.com"
    echo "  User git"
    [ -f "$HOME/.ssh/id_ed25519_personal" ] && echo "  IdentityFile ~/.ssh/id_ed25519_personal"
    echo "  IdentitiesOnly yes"
    echo ""
    echo "Host github-work"
    echo "  HostName github.com"
    echo "  User git"
    [ -f "$HOME/.ssh/id_ed25519_work" ] && echo "  IdentityFile ~/.ssh/id_ed25519_work"
    echo "  IdentitiesOnly yes"
  } >> "$SSHCFG"
  chmod 600 "$SSHCFG"
fi

# --- Back up any existing git config
if [ -f "$HOME/.gitconfig" ]; then
  cp -f "$HOME/.gitconfig" "$HOME/.gitconfig.bak.$(ts)"
fi

banner "Writing global ~/.gitconfig (sane, professional defaults)"
cat > "$HOME/.gitconfig" <<EOF
[user]
    name = ${NAME_PERSONAL}
    email = ${EMAIL_PERSONAL}
[init]
    defaultBranch = ${MAIN_BRANCH}
[core]
    editor = ${GIT_EDITOR}
    autocrlf = input
    filemode = false
[color]
    ui = auto
[pull]
    rebase = false
[push]
    default = simple
[fetch]
    prune = true
[gc]
    pruneExpire = now
    auto = 0
[alias]
    st = status -sb
    co = checkout
    br = branch -vv
    lg = log --oneline --graph --decorate
[credential]
    helper = store
# Safety: refuse unknown directory owners (use 'git config --global --add safe.directory <path>' if needed)
[safe]
    # empty; add with 'git config --global --add safe.directory <path>'
EOF

# Conditional includes (personal vs work directories)
# Mirrors the reddit suggestion to use includeIf per folder trees.
cat > "$HOME/.gitconfig-personal" <<EOF
[user]
    name = ${NAME_PERSONAL}
    email = ${EMAIL_PERSONAL}
[commit]
    gpgsign = false
EOF

cat > "$HOME/.gitconfig-work" <<EOF
[user]
    name = ${NAME_WORK}
    email = ${EMAIL_WORK}
[commit]
    gpgsign = false
EOF

# Attach the includeIf blocks (don’t duplicate)
if ! grep -q '\[includeIf "gitdir:' "$HOME/.gitconfig"; then
  cat >> "$HOME/.gitconfig" <<'EOF'

# Conditional identity by directory (trailing / matters)
[includeIf "gitdir:~/code/personal/"]
    path = ~/.gitconfig-personal

[includeIf "gitdir:~/code/work/"]
    path = ~/.gitconfig-work
EOF
fi

# Create directories referenced above
mkdir -p "$HOME/code/personal" "$HOME/code/work"

# --- Optional SSH-based commit signing (modern, gpgless)
read -r -p "Enable SSH-based commit signing with PERSONAL key? [y/N]: " yn || true
if [[ "$yn" =~ ^[Yy]$ ]] && [ -f "$HOME/.ssh/id_ed25519_personal.pub" ]; then
  SIGKEY="$(cat "$HOME/.ssh/id_ed25519_personal.pub")"
  git config --global gpg.format ssh
  git config --global user.signingkey "$SIGKEY"
  git config --global commit.gpgsign true
fi

# --- GitHub CLI install & login (best effort)
banner "Install GitHub CLI (gh) if available"
if ! command -v gh >/dev/null 2>&1; then
  # Try Termux package first
  if pkg list-all 2>/dev/null | grep -qE '^gh/'; then
    yes | pkg install gh || true
  else
    echo "No 'gh' package detected via pkg; you can install manually from GitHub releases later."
  fi
fi

if command -v gh >/dev/null 2>&1; then
  echo "Attempting 'gh auth login' (choose HTTPS+device or SSH as you prefer)..."
  # Device flow works well in Termux:
  gh auth login || true
  # Add keys (if generated)
  if [ -f "$HOME/.ssh/id_ed25519_personal.pub" ]; then
    gh ssh-key add "$HOME/.ssh/id_ed25519_personal.pub" -t "Termux ZFold4 (personal)" || true
  fi
  if [ -f "$HOME/.ssh/id_ed25519_work.pub" ]; then
    gh ssh-key add "$HOME/.ssh/id_ed25519_work.pub" -t "Termux ZFold4 (work)" || true
  fi
else
  echo "Tip: install gh later and run: gh auth login ; gh ssh-key add ~/.ssh/id_ed25519_personal.pub -t \"Termux personal\""
fi

banner "Quick sanity"
echo "git --version: $(git --version)"
echo "Global user:   $(git config --global user.name) <$(git config --global user.email)>"
echo "Editor:        $(git config --global core.editor)"
echo "Main branch:   $(git config --global init.defaultBranch)"
echo "Done. You can keep personal repos under ~/code/personal/, work under ~/code/work/."
echo
echo "NOTE: Using GitHub noreply addresses and conditional configs is recommended to avoid leaking identity details." 
echo "      (Reddit advice summarized: use noreply email, includeIf per directory, SSH keys, Host aliases.)"
