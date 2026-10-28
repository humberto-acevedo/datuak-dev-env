# Claude Code Context Persistence & Security Setup

## Overview

This document explains how Claude Code context is persisted across daily container restarts and how credentials are managed securely.

## Context Persistence

### What Gets Persisted

| Component | Location | Host Mount | Survives Restart? |
|-----------|----------|------------|-------------------|
| **Session transcripts** | `~/.claude/projects/` | ✅ Mounted | ✅ Yes |
| **Settings & config** | `~/.claude/settings.json` | ✅ Mounted | ✅ Yes |
| **Skills** | `~/.claude/skills/` | ✅ Mounted | ✅ Yes |
| **Memory** | `~/.claude/projects/<project>/memory/` | ✅ Mounted | ✅ Yes |
| **Keybindings** | `~/.claude/keybindings.json` | ✅ Mounted | ✅ Yes |
| **Agents** | `~/.claude/agents/` | ✅ Mounted | ✅ Yes |
| **Your code** | `/workspace` | ✅ Mounted | ✅ Yes |
| **SSH keys** | `~/.ssh/` | ✅ Mounted (ro) | ✅ Yes |
| **GitHub config** | `~/.config/gh/` | ✅ Mounted (ro) | ✅ Yes |

### Makefile Changes

The `Makefile` now mounts Claude config directories:

```makefile
DOCKER_VOLUMES := \
	-v "$$PWD/../..":/workspace \
	-v "$(HOME)/.claude:/home/devuser/.claude" \          # NEW: Claude context
	-v "$(HOME)/.gemini:/home/devuser/.gemini" \          # NEW: Gemini config
	-v "$(HOME)/.config/gh:/home/devuser/.config/gh:ro" \ # NEW: GitHub CLI
	...
```

**Result:** Every time you run `make claude`, all your sessions, settings, skills, and memory from yesterday are there.

## Credential & Security Management

### 🚫 Never Store These in `.env`:

```
❌ ANTHROPIC_API_KEY=sk-ant-v0-...
❌ KIRO_API_KEY=...
❌ GH_TOKEN=ghp_...
❌ AWS_SECRET_ACCESS_KEY=...
```

These are **never committed**, but they're still stored in plaintext on your local machine. Use AWS Secrets Manager instead.

### ✅ How Credentials Flow

```
┌─────────────────────────────────────┐
│ AWS SSO Login (24hr temporary)      │
│ $ make sso-login                    │
│   → Creates temporary AWS tokens    │
│   → Valid for ~12 hours             │
└─────────────────────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ AWS Secrets Manager (persistent)    │
│ $ make secrets-setup                │
│   → ANTHROPIC_API_KEY              │
│   → KIRO_API_KEY                   │
│   → Custom secrets                 │
└─────────────────────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ Container Runtime                   │
│ $ make claude                       │
│   1. ensure-sso: verify AWS tokens  │
│   2. fetch-secrets: load from SM    │
│   3. export-credentials: inject     │
│   4. Launch container               │
└─────────────────────────────────────┘
```

### Setup Steps

#### Step 1: AWS SSO Login (One-time per ~12 hours)

```bash
make sso-login
# or manually:
aws sso login --profile AdministratorAccess-539247495490
```

This creates temporary AWS credentials valid for ~12 hours.

#### Step 2: Store Persistent API Keys in AWS Secrets Manager

Create secrets for anything that doesn't expire:

```bash
# Anthropic API key (first-party API, not Bedrock)
aws secretsmanager create-secret \
  --name claude/anthropic-api-key \
  --secret-string 'sk-ant-v0-...'

# Kiro API key (if using Kiro)
aws secretsmanager create-secret \
  --name kiro/api-key \
  --secret-string 'your-kiro-key'

# List all secrets
aws secretsmanager list-secrets --filters Key=name,Values=claude,kiro
```

#### Step 3: Launch Container

```bash
make claude
```

This target now:
1. Checks AWS SSO session is valid (`ensure-sso`)
2. Fetches secrets from Secrets Manager (`fetch-secrets`)
3. Exports temporary AWS credentials
4. Launches Claude Code with context persistence

### Dockerfile: No Changes Needed

The Dockerfile already has:
- MCP server configuration (AWS, USAFacts)
- Claude settings with Bedrock enabled
- All tools pre-installed (claude, agy, kiro, terraform, etc.)

Credentials are injected at **runtime**, not baked into the image.

## Environment Variables

### Temporary (Injected at Runtime)

```bash
AWS_ACCESS_KEY_ID=      # From aws sso login
AWS_SECRET_ACCESS_KEY=  # From aws sso login
AWS_SESSION_TOKEN=      # From aws sso login
AWS_REGION=us-east-1    # From .env
```

These come from `aws configure export-credentials` and expire in ~12 hours.

### Persistent (From Secrets Manager)

```bash
ANTHROPIC_API_KEY=      # Fetched by make fetch-secrets
KIRO_API_KEY=           # Fetched by make fetch-secrets
```

### Static (From .env or Dockerfile)

```bash
AWS_PROFILE=AdministratorAccess-539247495490
AWS_ACCOUNT=539247495490
ANTHROPIC_MODEL=us.anthropic.claude-haiku-5-5
```

## Daily Workflow

```bash
# Day 1: Setup (one-time)
make sso-login
make secrets-setup
make claude
# → Work all day with Claude context

# Day 2: After container expires
make claude
# → ensure-sso: checks if ~12hr session expired
# → If expired: re-runs sso-login automatically
# → fetch-secrets: loads ANTHROPIC_API_KEY
# → All context from Day 1 is there ✅

# Every ~12 hours after that
make claude
# → Same flow, auto-refreshes SSO if needed
```

## Verification

```bash
# Test everything
make verify

# This checks:
# ✅ Claude settings.json
# ✅ AGY/Gemini config
# ✅ MCP servers connected (AWS, USAFacts)
# ✅ Models configured (Haiku, Sonnet, Opus)
# ✅ Tools installed (claude, agy, kiro, aws, gh, terraform)
# ✅ AWS credentials valid
# ✅ GitHub authentication
# ✅ SSH directory and keys
```

## Help

```bash
make help
```

Shows all targets and their purpose.

## Troubleshooting

### "AWS credentials expired"

```bash
make sso-login
```

### "ANTHROPIC_API_KEY not set"

```bash
make fetch-secrets
# Then check: aws secretsmanager list-secrets
```

### Container doesn't have yesterday's context

Check that `~/.claude` is mounted:

```bash
docker inspect <container-id> | grep -A 5 claude
# Should show: /home/devuser/.claude → /Users/yourname/.claude
```

If missing, run `make clean` and `make claude` again.

### "gh CLI not authenticated"

```bash
gh auth login
# Stores token in macOS Keychain or Linux secure storage
```

## Security Summary

| Item | Storage | Injection | TTL |
|------|---------|-----------|-----|
| AWS temp tokens | Host system | `aws configure export-credentials` | ~12 hours |
| ANTHROPIC_API_KEY | AWS Secrets Manager | `aws secretsmanager get-secret-value` | None (persistent) |
| KIRO_API_KEY | AWS Secrets Manager | Manual or script | None (persistent) |
| GH_TOKEN | macOS Keychain or Linux secure store | `gh auth login` | None (persistent) |
| `.env` local vars | Host `.env` file | Docker `--env-file` | None (session) |
| Claude context | Host `~/.claude` dir | Docker volume mount | None (persistent) |

**Key principle:** Permanent credentials live in AWS Secrets Manager. Temporary credentials are short-lived and auto-refreshed. Nothing is hardcoded in images or containers.
