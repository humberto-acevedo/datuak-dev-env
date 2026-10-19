---
name: docker-entrypoint-hang
description: Docker container hangs during initialization when running "make shell"
metadata:
  type: project
---

## Issue
`make shell` command hangs during Docker container initialization, blocking at the entrypoint.sh execution.

## Root Cause Analysis

### Primary Culprit: Secrets Manager Call (entrypoint.sh:50)

The hang is likely caused by **line 50 in entrypoint.sh**:
```bash
GEMINI_API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --region "$REGION" \
  --query SecretString \
  --output text)
```

This call is **only intended for the `agy` command**, but the condition check is:
```bash
if [[ "${1:-}" == "agy" ]]; then
```

**Problem**: When running `make shell`, the command is `/bin/bash`, so `${1:-}` is empty or "/bin/bash", not "agy". The Secrets Manager call **should not execute**, but there may be a logic issue causing it to run anyway.

### Secondary Culprits: Other Blocking Calls

1. **SSH key operations (lines 63-75)**
   - `ssh-keyscan -H github.com` - Network call that could timeout
   - `find "${HOME}/.ssh" -type f -exec chmod 600 {} \;` - Could hang if SSH mount is slow

2. **Git configuration (lines 77-79)**
   - `git config --global` calls should be fast, but could fail if permissions issue

### Tertiary Issues: AWS Bedrock Environment

The Dockerfile sets:
```dockerfile
ENV ANTHROPIC_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
```

But based on your earlier Bedrock investigation, **Haiku 5.5 is not accessible** in these accounts. If anything in initialization tries to validate these models, it would fail/hang.

## Why It Hangs (Not Just Fails)

1. **AWS CLI timeout** - By default, AWS CLI can hang for ~60 seconds on credential/network issues
2. **SSH keyscan** - If GitHub is unreachable or DNS is slow, `ssh-keyscan` can timeout
3. **read-only mount permission issues** - `find` and `chmod` on mounted volumes can hang

## Solution

### Immediate Fix: Add Timeout to Secrets Manager Call

Modify entrypoint.sh line 50-58:

```bash
if [[ "${1:-}" == "agy" ]]; then
  SECRET_NAME="${GEMINI_SECRET_NAME:-GoogleGeminiAPIKeyiMac}"
  MCP_ENDPOINT="${MCP_AWS_ENDPOINT:-https://aws-mcp.us-east-1.api.aws/mcp}"
  REGION="${AWS_REGION:-us-east-1}"

  echo "Fetching Antigravity/Gemini API key from Secrets Manager..."
  
  # Add timeout to prevent indefinite hang
  GEMINI_API_KEY=$(timeout 10 aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query SecretString \
    --output text 2>/dev/null || echo "")
  
  if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "⚠️  Warning: Could not retrieve secret '$SECRET_NAME'. Proceeding anyway." >&2
  else
    export GEMINI_API_KEY MCP_ENDPOINT
    echo "✅ GEMINI_API_KEY set."
  fi
fi
```

### Better Fix: Make AWS Calls Non-Blocking

Add early exit for non-agy/non-kiro commands:

```bash
#!/bin/bash
set -euo pipefail

# Early exit for bash/simple commands - skip AWS calls
if [[ "${1:-}" != "agy" && "${1:-}" != "kiro-cli"* ]]; then
  # Skip AWS-dependent initialization for simple shell/bash
  exec "$@"
fi

# (rest of script continues for agy/kiro commands)
```

### Robust Fix: Parallelize and Timeout All Network Calls

```bash
# SSH keyscan with timeout
(ssh-keyscan -H github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true) &
keyscan_pid=$!

# Secrets Manager with timeout
if [[ "${1:-}" == "agy" ]]; then
  GEMINI_API_KEY=$(timeout 5 aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$REGION" \
    --query SecretString \
    --output text 2>/dev/null || echo "")
fi

# Wait for background jobs with timeout
wait $keyscan_pid 2>/dev/null || true

# Continue with normal execution
exec "$@"
```

## Testing the Fix

After changes, test with:
```bash
make shell
# Should drop to bash within ~5 seconds, not hang

make test
# Should pass all configuration checks

make shell
# Run inside container:
  env | grep ANTHROPIC
  aws sts get-caller-identity
  echo "✅ Container initialized successfully"
```

## Prevention

1. **Add timeout wrapper** to all external API calls
2. **Skip AWS calls** for non-credential-dependent commands
3. **Add debug flag** to entrypoint.sh for troubleshooting:
   ```bash
   DEBUG=${DEBUG:-0}
   [[ $DEBUG == 1 ]] && set -x
   ```
4. **Document required environment variables** needed for specific commands

## Bedrock Note

The current Dockerfile references Bedrock models that are blocked in your accounts:
```dockerfile
ENV ANTHROPIC_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
```

This should be updated once AWS Sales enables Bedrock access. The prefix `us.` suggests cross-region inference profiles, but these are still blocked per earlier diagnosis.
