#!/bin/bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

# Attempt initial clock sync on startup (script baked into image)
/usr/local/bin/sync-time 2>/dev/null || true

# If launching kiro, verify KIRO_API_KEY is set
if [[ "${1:-}" == "kiro-cli" ]]; then
  if [[ -z "${KIRO_API_KEY:-}" ]]; then
    echo "Warning: KIRO_API_KEY is not set. Authenticate with 'kiro-cli login' (device flow) or set KIRO_API_KEY in .env (Pro+ subscribers)." >&2
  fi
fi

# Verify AWS Agent Toolkit dependencies are available
if command -v uv &> /dev/null; then
  echo "✅ AWS MCP dependencies available (uv installed)"
else
  echo "⚠️  uv not found in PATH - AWS MCP proxy may not work"
fi

# Verify Antigravity (AGY) MCP configuration exists (generated at build time)
if [[ ! -s /root/.gemini/config/mcp_config.json ]]; then
  echo "⚠️  Warning: AGY MCP configuration not found. This should have been generated at build time."
fi


# If launching agy, fetch the API key from Secrets Manager
if [[ "${1:-}" == "agy" ]]; then
  SECRET_NAME="${GEMINI_SECRET_NAME:-GoogleGeminiAPIKeyiMac}"
  MCP_ENDPOINT="${MCP_AWS_ENDPOINT:-https://aws-mcp.us-east-1.api.aws/mcp}"
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
  export GEMINI_API_KEY MCP_ENDPOINT
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

# Configure git identity (parameterized for multi-user support)
git config --global user.email "${GIT_USER_EMAIL:-humberto.acevedo@datuak.ai}"
git config --global user.name "${GIT_USER_NAME:-Humberto Acevedo}"

exec "$@"
