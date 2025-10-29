#!/data/data/com.termux/files/usr/bin/bash
# RELAXED STATUS — never exits non-zero
printf "SSH_AUTH_SOCK=%s\n" "${SSH_AUTH_SOCK:-<unset>}"
printf "SSH_AGENT_PID=%s\n" "${SSH_AGENT_PID:-<unset>}"
echo
echo "ssh-add -l:"
ssh-add -l 2>&1 || true
# Always succeed
true
