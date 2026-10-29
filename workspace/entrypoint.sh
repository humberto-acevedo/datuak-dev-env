#!/bin/bash
set -eo pipefail
# Removed '-u' from set flags to avoid unset variable errors when optional vars are missing

# Tools (claude, agy, kiro) are installed globally to /usr/local/bin at build time
# so no extra PATH manipulation is needed here.

echo "🤖 Claude Code configuration"

# Claude provider: Bedrock needs inference profile IDs (us.anthropic.<model>);
# the first-party API (WIF) uses the plain model names set in the Dockerfile
if [[ "${CLAUDE_CODE_USE_BEDROCK:-0}" == "1" ]]; then
  for var in ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL; do
    if [[ -n "${!var:-}" && "${!var}" != us.anthropic.* ]]; then
      export "$var=us.anthropic.${!var}"
    fi
  done
  echo "   → Claude provider: AWS Bedrock ($ANTHROPIC_MODEL)"
else
  echo "   → Claude provider: Anthropic API via WIF ($ANTHROPIC_MODEL)"
  if [[ -z "${ANTHROPIC_FEDERATION_RULE_ID:-}" || ! -s "${ANTHROPIC_IDENTITY_TOKEN_FILE:-/nonexistent}" ]]; then
    echo "⚠️  WIF is not fully configured (federation IDs or identity token missing); Claude Code will ask to log in." >&2
    echo "   Launch through the Makefile (make claude) with the ANTHROPIC_* IDs set in .env." >&2
  fi
fi

# Attempt initial clock sync on startup (script baked into image)
# Use --max-time 8 to allow DNS resolution time; continue on timeout
/usr/local/bin/sync-time || true

# Fix workspace ownership: devuser for main workspace, root for Ideas (restricted)
# Use timeout to avoid hanging on large bind-mounted filesystems
if /usr/bin/timeout 5 chown -R devuser:devuser /workspace 2>/dev/null; then
  true
else
  # Large filesystem or mount issues; skip and continue
  true
fi
if [[ -d /workspace/Ideas ]]; then
  /usr/bin/timeout 3 chown -R root:root /workspace/Ideas 2>/dev/null || true
fi

# If launching kiro, verify KIRO_API_KEY is set
if [[ "${1:-}" == kiro-cli* ]]; then
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
if [[ ! -s "${HOME}/.gemini/config/mcp_config.json" ]]; then
  echo "⚠️  Warning: AGY MCP configuration not found. This should have been generated at build time."
fi

# If launching agy, fetch the API key from Secrets Manager (with timeout to prevent hang)
if [[ "${1:-}" == "agy" ]]; then
  SECRET_NAME="${GEMINI_SECRET_NAME:-GoogleGeminiAPIKeyiMac}"
  MCP_ENDPOINT="${MCP_AWS_ENDPOINT:-https://aws-mcp.us-east-1.api.aws/mcp}"
  REGION="${AWS_REGION:-us-east-1}"

  echo "Fetching Antigravity/Gemini API key from Secrets Manager (secret: $SECRET_NAME, region: $REGION)..."

  # Add timeout to prevent indefinite hang on credential/network issues
  GEMINI_API_KEY=$(timeout 5 aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query SecretString \
    --output text 2>/dev/null || echo "")

  if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "❌ Error: Could not retrieve secret '$SECRET_NAME'." >&2
    echo "   This could be due to:" >&2
    echo "   • AWS credentials expired or missing" >&2
    echo "   • Network timeout (5 second limit)" >&2
    echo "   • Secret not found in Secrets Manager" >&2
    echo "   • Insufficient IAM permissions" >&2
    exit 1
  fi
  export GEMINI_API_KEY MCP_ENDPOINT
  echo "✅ GEMINI_API_KEY set."
fi

# Configure git authentication: SSH if keys are mounted, HTTPS token otherwise
if [[ -d "${HOME}/.ssh" ]] && ls "${HOME}/.ssh/id_"* &>/dev/null 2>/dev/null; then
  chmod 700 "${HOME}/.ssh" 2>/dev/null || true
  find "${HOME}/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true

  # Tell gh CLI to use SSH for git operations
  git config --global url."git@github.com:".insteadOf "https://github.com/"
  echo "✅ Git configured to use mounted SSH keys"
else
  # No SSH keys: resolve token from env var (GH_TOKEN/GITHUB_TOKEN) or gh CLI
  RESOLVED_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}}"
  if [[ -n "$RESOLVED_TOKEN" ]]; then
    echo "https://${GIT_USER_NAME:-humberto-acevedo}:${RESOLVED_TOKEN}@github.com" > "${HOME}/.git-credentials"
    chmod 600 "${HOME}/.git-credentials"
    echo "✅ Git credentials populated from token"
  else
    echo "⚠️  No SSH keys and no GH_TOKEN found — git pull from private repos will fail"
    echo "   Pass a token with: docker run -e GH_TOKEN=\$(gh auth token) ..."
  fi
fi

# Configure git identity (parameterized for multi-user support)
git config --global user.email "${GIT_USER_EMAIL:-humberto.acevedo@datuak.ai}"
git config --global user.name "${GIT_USER_NAME:-Humberto Acevedo}"

exec "$@"
