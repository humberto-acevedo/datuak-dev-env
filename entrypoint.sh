#!/bin/bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

# Setup on-demand time sync utility
cat << 'EOF' > /usr/local/bin/sync-time
#!/bin/bash
echo "==> Synchronizing system clock with AWS..."
REMOTE_DATE=$(curl -sI --max-time 4 https://aws.amazon.com 2>/dev/null | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r')
if [[ -z "$REMOTE_DATE" ]]; then
  echo "Warning: Could not fetch AWS server time to sync clock." >&2
  exit 1
fi
echo "Time before sync: $(date -u)"
if date -s "$REMOTE_DATE" >/dev/null 2>&1; then
  echo "Time after sync : $(date -u)"
  echo "✅ Clock successfully synchronized."
else
  echo "⚠️  Failed to set clock. (Did you run container with --cap-add=SYS_TIME?)" >&2
fi
EOF
chmod +x /usr/local/bin/sync-time
ln -sf /usr/local/bin/sync-time /usr/local/bin/sync-clock 2>/dev/null || true

# Attempt initial clock sync on startup
/usr/local/bin/sync-time 2>/dev/null || true

# If launching kiro, verify KIRO_API_KEY is set
if [[ "${1:-}" == "kiro-cli" ]]; then
  if [[ -z "${KIRO_API_KEY:-}" ]]; then
    echo "Warning: KIRO_API_KEY is not set. Authenticate with 'kiro-cli login' (device flow) or set KIRO_API_KEY in .env (Pro+ subscribers)." >&2
  fi
fi

# If launching agy, fetch the API key from Secrets Manager first
if [[ "${1:-}" == "agy" ]]; then
  SECRET_NAME="${GEMINI_SECRET_NAME:-GoogleGeminiAPIKeyiMac}"
  REGION="${AWS_REGION:-us-east-1}"

  echo "Fetching Antigravity/Gemini API key from Secrets Manager (secret: $SECRET_NAME, region: $REGION)..."
  GEMINI_API_KEY=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query SecretString \
    --output text)
  if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "Error: Could not retrieve secret '$SECRET_NAME'." >&2
    exit 1
  fi
  export GEMINI_API_KEY
  echo "GEMINI_API_KEY set."
fi

# Ensure correct permissions on mounted SSH keys (read-only mount may have wrong perms inside container)
if [[ -d /root/.ssh ]]; then
  chmod 700 /root/.ssh 2>/dev/null || true
  find /root/.ssh -type f -exec chmod 600 {} \; 2>/dev/null || true

  # Trust GitHub's host key to avoid interactive prompts
  if [[ ! -f /root/.ssh/known_hosts ]] || ! grep -q github.com /root/.ssh/known_hosts 2>/dev/null; then
    ssh-keyscan -H github.com >> /root/.ssh/known_hosts 2>/dev/null || true
  fi

  # Tell gh CLI to use SSH for git operations
  git config --global url."git@github.com:".insteadOf "https://github.com/"
fi

# Configure git identity
git config --global user.email "humberto.acevedo@datuak.ai"
git config --global user.name "Humberto Acevedo"

exec "$@"
