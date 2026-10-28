# Multi-Host Claude Context Sync — Phase 1 (One-Way S3 Master)

## Overview

Phase 1 implements automatic context synchronization across two hosts (Mac + AWS workspace) using AWS S3 as the single source of truth.

**Architecture:**
```
Mac (~/.claude/)          AWS Workspace (~/.claude/)
     ↓                           ↓
  [sync-to-s3]          [sync-from-s3]
     ↓                           ↓
        AWS S3 (master)
     ↑                           ↑
  [sync-from-s3]          [sync-to-s3]
```

**Key Features:**
- ✅ One-way master (S3) prevents conflicts
- ✅ Automatic sync before/after sessions
- ✅ Versioning for rollback/recovery
- ✅ AES-256 encryption
- ✅ Public access blocked
- ✅ Per-hostname isolation (`claude-context-<ACCOUNT_ID>/<HOSTNAME>/`)

## Quick Start (5 Minutes)

### Step 1: One-Time Setup

```bash
cd /workspace/datuak-dev-env/workspace

# Setup S3 bucket, encryption, versioning
make sync-setup

# Output:
# ✅ Setup complete!
# Configuration:
#   Account ID:    539247495490
#   Bucket:        claude-context-539247495490
#   Region:        us-east-1
#   Hostname:      humberto-macbook
#   Profile:       AdministratorAccess-539247495490
```

**What it does:**
1. Creates S3 bucket: `claude-context-<ACCOUNT_ID>`
2. Enables versioning (for history/rollback)
3. Enables AES-256 encryption
4. Blocks public access
5. Tests read/write access
6. Adds tags for cost tracking

### Step 2: Download Existing Context (First Time)

```bash
make sync-from-s3

# Output:
# 📥 Downloading ~/.claude from S3...
# ✅ Context synced from S3
```

This downloads any existing Claude context from S3 to your local machine.

### Step 3: Launch Claude

```bash
make claude

# Automatically:
# 1. Downloads latest context from S3
# 2. Launches Claude Code
# 3. When you exit, uploads changes back to S3
```

That's it! Context is now synced automatically.

## Daily Workflow

### Scenario 1: Work on Mac, Continue on AWS Workspace

```bash
# Mac (9:00 AM)
$ cd datuak-dev-env/workspace
$ make claude
# → Downloads latest from S3
# → Opens Claude Code
# → Work for 2 hours
# → Exit Claude
# → Uploads context to S3 ✅

# AWS Workspace (11:30 AM)
$ cd datuak-dev-env/workspace
$ make claude
# → Downloads latest from S3 (includes Mac's work)
# → Claude sessions show Mac's transcripts
# → Continue from where Mac left off
# → Exit
# → Uploads changes to S3 ✅
```

### Scenario 2: Check What's on S3

```bash
make list-remote-contexts

# Output:
# 📋 Remote Claude contexts in S3:
# claude-context-539247495490/humberto-macbook/.claude/projects/...
# claude-context-539247495490/humberto-aws/.claude/projects/...
```

### Scenario 3: Manual Sync

```bash
# Download without launching Claude
make sync-from-s3

# Upload current context
make sync-to-s3
```

## Implementation Details

### Makefile Targets

| Target | Purpose | Auto-called? |
|--------|---------|--------------|
| `make sync-setup` | One-time S3 bucket setup | No |
| `make sync-from-s3` | Download context from S3 | ✅ Yes (before session) |
| `make sync-to-s3` | Upload context to S3 | ✅ Yes (after session) |
| `make list-remote-contexts` | List remote contexts | No |

### Makefile Variables

```makefile
CLAUDE_CONTEXT_BUCKET ?= claude-context-$(ACCOUNT_ID)
HOSTNAME=$(shell hostname -s)
```

Auto-computed from:
- **Account ID:** `aws sts get-caller-identity`
- **Hostname:** `hostname -s` (e.g., `humberto-macbook`, `humberto-aws`)

### Setup Script: `scripts/sync-setup.sh`

```bash
# Location: /workspace/datuak-dev-env/workspace/scripts/sync-setup.sh
# Execution: make sync-setup (or bash scripts/sync-setup.sh)

Steps:
1. Create S3 bucket
2. Enable versioning
3. Enable AES-256 encryption
4. Block public access
5. Add tags (Purpose, CreatedBy, Account)
6. Test access (read/write)
```

### Sync Directories

```
~/.claude/
  ├── projects/
  │   └── <project-name>/
  │       ├── <session-id>/
  │       │   └── transcript.md
  │       └── memory/
  │           └── ...
  ├── skills/
  │   └── ...
  ├── settings.json
  ├── settings.local.json
  ├── keybindings.json
  └── agents/
```

**Excluded from sync:**
- `.tmp` files
- `.git/` directories
- `.lock` files
- `.DS_Store`

## S3 Bucket Structure

```
s3://claude-context-539247495490/
├── humberto-macbook/.claude/
│   ├── projects/
│   ├── skills/
│   ├── settings.json
│   └── ...
└── humberto-aws/.claude/
    ├── projects/
    ├── skills/
    ├── settings.json
    └── ...
```

Each hostname gets its own directory. This prevents hostname conflicts when syncing.

## Recovery & Versioning

### List All Versions of a File

```bash
aws s3api list-object-versions \
  --bucket claude-context-539247495490 \
  --region us-east-1 \
  | jq '.Versions[] | {Key, VersionId, LastModified}'
```

### Restore a Specific Version

```bash
aws s3api get-object \
  --bucket claude-context-539247495490 \
  --key humberto-macbook/.claude/projects/my-project/transcript.md \
  --version-id <VERSION_ID> \
  transcript.md.backup
```

### View Versioning Status

```bash
aws s3api get-bucket-versioning \
  --bucket claude-context-539247495490 \
  --region us-east-1
```

Output: `Status: Enabled`

## Security

### What's Encrypted?

- ✅ Data in transit (HTTPS)
- ✅ Data at rest (AES-256 on S3)
- ✅ Versioning enabled (recovery without backups)

### What's NOT Encrypted?

- Bucket name (public on S3)
- File paths (visible in S3 console)
- Object metadata

**Recommendation:** Don't store highly sensitive credentials in Claude context (use AWS Secrets Manager instead).

## Environment Variables

| Variable | Value | Source |
|----------|-------|--------|
| `CLAUDE_CONTEXT_BUCKET` | `claude-context-<ACCOUNT_ID>` | Makefile |
| `HOSTNAME` | `hostname -s` (e.g., `humberto-macbook`) | Makefile |
| `AWS_PROFILE` | From CLI or `.env` | Config |
| `REGION` | From CLI or `.env` (default: `us-east-1`) | Config |

## Troubleshooting

### "Bucket already exists"

Normal — just means another host already ran `make sync-setup`. Both hosts share the same S3 bucket and upload to different directories.

### "Access Denied"

Check AWS credentials:
```bash
make ensure-sso
aws sts get-caller-identity --profile $(AWS_PROFILE)
```

### "No remote contexts found"

First sync from a host that has context:
```bash
# On host with Claude context
make sync-to-s3

# On other host
make sync-from-s3
```

### "Disk space full after syncing"

Claude context usually ~50-100MB. If larger, check for:
- Large file attachments in sessions
- Debug logs
- Temporary files (automatically excluded)

## Monitoring

### Check Bucket Size

```bash
aws s3 ls s3://claude-context-$(aws sts get-caller-identity --query Account --output text)/ \
  --recursive \
  --human-readable \
  | tail -1
```

### Check Last Sync Time

```bash
aws s3api head-object \
  --bucket claude-context-539247495490 \
  --key humberto-macbook/.claude/settings.json \
  | jq '.LastModified'
```

### View Upload/Download Stats

```bash
# See all sync operations in bash history
history | grep "sync-"
```

## Costs

**Estimated monthly cost:**
- Storage: ~$0.02–0.10 (100MB of context at 50MB per host)
- Requests: ~$0.01 (sync-from/sync-to ~ 1-10 requests per day)
- Versioning: ~$0.01 (old versions auto-retained)

**Total: ~$0.15–0.25/month** (negligible)

## What's Next: Phase 2?

When Phase 1 is comfortable, upgrade to:
- **Conflict resolution** (timestamps + metadata)
- **Incremental sync** (only changed files)
- **Bandwidth optimization** (delta sync)

See `MULTI_HOST_SYNC_PHASE_2.md` (future).

## Quick Reference

```bash
# Setup (one-time)
make sync-setup

# Daily usage (automatic)
make claude               # Auto-syncs before/after

# Manual sync
make sync-from-s3         # Download from S3
make sync-to-s3           # Upload to S3
make list-remote-contexts # See what's synced
```

---

**Questions?** See `CLAUDE_CONTEXT_SETUP.md` for general context persistence architecture.
