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
│   → KIRO_API_KEY                   │
│   → Custom secrets                 │
└─────────────────────────────────────┘
               ↓
┌─────────────────────────────────────┐
│ Container Runtime                   │
│ $ make claude                       │
│   1. ensure-sso: verify AWS tokens  │
│   2. export-credentials: inject     │
│   3. mint WIF token (refreshed 60s) │
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

Create secrets for anything that doesn't expire. Claude Code needs none: it
authenticates with Anthropic WIF (see [ANTHROPIC_WIF_SETUP.md](ANTHROPIC_WIF_SETUP.md)).

```bash
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
2. Exports temporary AWS credentials
3. Mints the Anthropic WIF identity token (`scripts/with-wif-token.sh`)
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
KIRO_API_KEY=           # Secrets Manager or kiro-cli login
```

### Static (From .env or Dockerfile)

```bash
AWS_PROFILE=AdministratorAccess-539247495490
AWS_ACCOUNT=539247495490
ANTHROPIC_MODEL=claude-haiku-5-5        # Dockerfile; Bedrock prefix added when CLAUDE_CODE_USE_BEDROCK=1
ANTHROPIC_FEDERATION_RULE_ID=fdrl_...   # .env; plus the org, service account, and workspace IDs
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
# → mints a fresh WIF identity token for Claude Code
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

### Claude Code asks to log in

```bash
make wif-setup ARGS=--check   # AWS side: federation enabled, token mints
make wif-test                 # Claude Code in the container answers via WIF
```

Also check that the `ANTHROPIC_*` IDs are in `workspace/.env`.

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
| Anthropic WIF token | Minted on host, mounted read-only | `scripts/with-wif-token.sh` | 15 min, refreshed every 60 s |
| KIRO_API_KEY | AWS Secrets Manager | Manual or script | None (persistent) |
| GH_TOKEN | macOS Keychain or Linux secure store | `gh auth login` | None (persistent) |
| `.env` local vars | Host `.env` file | Docker `--env-file` | None (session) |
| Claude context | Host `~/.claude` dir | Docker volume mount | None (persistent) |

**Key principle:** Permanent credentials live in AWS Secrets Manager. Temporary credentials are short-lived and auto-refreshed. Nothing is hardcoded in images or containers.

## Pending: image Claude settings are hidden

The image writes `~/.claude/settings.json` at build time (the `aws:*` permission and
`AWS_REGION` env), but `make` mounts the host `~/.claude` over it, so those settings
never apply in the container. AGY had the same problem with `~/.gemini`; the entrypoint
now merges its MCP servers at container start.

Planned fix: merge the image settings into the mounted file at start, additively
(add missing keys only). Because `~/.claude` syncs to S3 and is shared by every host,
including Claude Code on the Mac, only host-safe keys may be merged. Container-specific
values (provider switch, model names) stay in the image ENV and the Makefile: a
`CLAUDE_CODE_USE_BEDROCK` key in the settings `env` block overrides `docker run -e`.
