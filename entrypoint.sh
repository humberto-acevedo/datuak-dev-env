#!/bin/bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

# If launching gemini, fetch the API key from Secrets Manager first
if [[ "${1:-}" == "gemini" ]]; then
  SECRET_NAME="${GEMINI_SECRET_NAME:-GoogleGeminiAPIKeyiMac}"
  REGION="${AWS_REGION:-us-east-1}"
  echo "Fetching Gemini API key from Secrets Manager (secret: $SECRET_NAME, region: $REGION)..."
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

exec "$@"
