#!/data/data/com.termux/files/usr/bin/bash
ENV_FILE="$HOME/.ssh/agent.env"

# Try to stop the current agent; ignore errors
ssh-agent -k >/dev/null 2>&1 || true
[ -f "$ENV_FILE" ] && rm -f "$ENV_FILE" >/dev/null 2>&1 || true
echo "ssh-agent stopped and env cleared."
# Always succeed
true
