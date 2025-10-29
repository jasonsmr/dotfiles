#!/data/data/com.termux/files/usr/bin/bash
# RELAXED MODE: no -e, -u, or pipefail; all errors are soft.
# Purpose: start/reuse ssh-agent, add keys, ensure SSH signing config.

ENV_FILE="$HOME/.ssh/agent.env"
ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"
PERSONAL_KEY="$HOME/.ssh/id_ed25519_personal"
WORK_KEY="$HOME/.ssh/id_ed25519_work"

log() { [ "${RF_AGENT_VERBOSE:-0}" = "1" ] && printf "[rf-agent] %s\n" "$*"; }

ensure_dirs() {
  mkdir -p "$HOME/.ssh" >/dev/null 2>&1
  chmod 700 "$HOME/.ssh" >/dev/null 2>&1 || true
}

agent_alive() {
  [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ] && ssh-add -l >/dev/null 2>&1
}

source_env_if_any() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE" 2>/dev/null || true
  fi
}

write_env() {
  : > "$ENV_FILE" 2>/dev/null
  {
    echo "export SSH_AUTH_SOCK='$SSH_AUTH_SOCK'"
    echo "export SSH_AGENT_PID='$SSH_AGENT_PID'"
  } >> "$ENV_FILE"
  chmod 600 "$ENV_FILE" >/dev/null 2>&1 || true
}

start_agent() {
  log "starting new ssh-agent"
  # Start and capture vars without causing shell exit on failure
  eval "$(ssh-agent -s 2>/dev/null)" >/dev/null 2>&1 || true
  # If eval failed, try again once:
  if ! agent_alive; then
    eval "$(ssh-agent -s 2>/dev/null)" >/dev/null 2>&1 || true
  fi
  write_env
}

reuse_or_start_agent() {
  source_env_if_any
  if agent_alive; then
    log "reusing existing agent: pid=${SSH_AGENT_PID:-?} sock=${SSH_AUTH_SOCK:-?}"
    return
  fi
  start_agent
}

key_fingerprint() {
  ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'
}

key_loaded() {
  local fp
  fp="$(key_fingerprint "$1")"
  [ -n "$fp" ] && ssh-add -l 2>/dev/null | grep -q "$fp"
}

add_key_if_present() {
  local key="$1"
  [ -f "$key" ] || return 0
  if key_loaded "$key"; then
    log "key already loaded: $key"
  else
    log "adding key: $key"
    ssh-add "$key" >/dev/null 2>&1 || true
  fi
}

ensure_allowed_signers() {
  touch "$ALLOWED_SIGNERS" 2>/dev/null || true
  chmod 600 "$ALLOWED_SIGNERS" 2>/dev/null || true

  if [ -f "${PERSONAL_KEY}.pub" ] && ! grep -q "^jasonsmr " "$ALLOWED_SIGNERS" 2>/dev/null; then
    printf "jasonsmr %s\n" "$(cat "${PERSONAL_KEY}.pub")" >> "$ALLOWED_SIGNERS" 2>/dev/null || true
  fi
  if [ -f "${WORK_KEY}.pub" ] && ! grep -q "^work " "$ALLOWED_SIGNERS" 2>/dev/null; then
    printf "work %s\n" "$(cat "${WORK_KEY}.pub")" >> "$ALLOWED_SIGNERS" 2>/dev/null || true
  fi
}

ensure_git_signing_config() {
  git config --global gpg.format ssh >/dev/null 2>&1 || true
  git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS" >/dev/null 2>&1 || true
  if [ -f "${PERSONAL_KEY}.pub" ]; then
    git config --global user.signingkey "${PERSONAL_KEY}.pub" >/dev/null 2>&1 || true
  fi
  git config --global commit.gpgsign true >/dev/null 2>&1 || true
}

# ---- Main ----
ensure_dirs
reuse_or_start_agent
# Export so current shell benefits even if we sourced agent.env earlier
export SSH_AUTH_SOCK SSH_AGENT_PID
add_key_if_present "$PERSONAL_KEY"
add_key_if_present "$WORK_KEY"
ensure_allowed_signers
ensure_git_signing_config
log "ready: pid=${SSH_AGENT_PID:-?} sock=${SSH_AUTH_SOCK:-?}"

# Never exit non-zero (avoid killing terminals that autoload this)
true
