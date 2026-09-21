# Bedrock Model Access Audit

**Date:** 2026-09-21
**Region:** us-east-1

---

## Summary

Claude Code was falling back from Opus 5 to Opus 4.6 on startup. Investigation revealed that multiple Claude models on Bedrock are **sales-gated** — the foundation model agreement (EULA) is accepted and inference profiles show ACTIVE, but `InvokeModel` returns `AccessDeniedException`. This is an account-level gate that requires AWS Sales to enable.

---

## Access Test Results

Tested all `us.anthropic.claude-*` inference profiles with a minimal `InvokeModel` call.

### Available (invoke confirmed)

| Inference Profile ID | Model |
|---|---|
| `us.anthropic.claude-opus-4-6-v1` | Claude Opus 4.6 |
| `us.anthropic.claude-opus-4-5-20251101-v1:0` | Claude Opus 4.5 |
| `us.anthropic.claude-sonnet-4-6` | Claude Sonnet 4.6 |
| `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Claude Sonnet 4.5 |
| `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Claude Haiku 4.5 |

### Denied (sales-gated)

All return: `AccessDeniedException: <model> is not available for this account. For additional access options, contact AWS Sales.`

| Inference Profile ID | Model |
|---|---|
| `us.anthropic.claude-opus-5` | Claude Opus 5 |
| `us.anthropic.claude-opus-4-8` | Claude Opus 4.8 |
| `us.anthropic.claude-opus-4-7` | Claude Opus 4.7 |
| `us.anthropic.claude-opus-4-1-20250805-v1:0` | Claude Opus 4.1 |
| `us.anthropic.claude-sonnet-5` | Claude Sonnet 5 |
| `us.anthropic.claude-sonnet-4-20250514-v1:0` | Claude Sonnet 4 |
| `us.anthropic.claude-fable-5-1` | Claude Fable 5.1 |
| `us.anthropic.claude-fable-5` | Claude Fable 5 |
| `us.anthropic.claude-3-sonnet-20240229-v1:0` | Claude 3 Sonnet |
| `us.anthropic.claude-3-haiku-20240307-v1:0` | Claude 3 Haiku |

---

## Root Cause

The Dockerfile ENV vars and Python config generator both hardcoded gated model IDs:

```dockerfile
# BEFORE (broken)
ENV ANTHROPIC_SMALL_FAST_MODEL=us.anthropic.claude-sonnet-5        # DENIED
ENV ANTHROPIC_LARGE_MODEL=us.anthropic.claude-opus-5                # DENIED
ENV ANTHROPIC_ULTRA_FAST_MODEL=us.anthropic.claude-fable-5-1        # DENIED
```

Claude Code probes these on startup, gets rejections, and falls back. The Opus fallback (`opus-4-6-v1`) worked, but Sonnet and Fable had no implicit fallback, causing repeated errors.

---

## Changes Made

### Dockerfile

- `ANTHROPIC_LARGE_MODEL`: `opus-5` → `opus-4-6-v1`
- `ANTHROPIC_SMALL_FAST_MODEL`: `sonnet-5` → `sonnet-4-6`
- `ANTHROPIC_ULTRA_FAST_MODEL`: `fable-5-1` → `haiku-4-5` (no Fable available)
- Python config generator defaults updated to match

### entrypoint.sh

- Removed misleading "all models including Fable" from startup message

### .env.example

- Updated commented model overrides to use actual env var names and available IDs
- Added reference to access audit doc

### openclaw-bedrock/scripts/

- `bootstrap.sh`: `CLAUDE_SONNET_MODEL` updated from `sonnet-4-5` to `sonnet-4-6`
- `openclaw-config.json.tpl`: `deepFallback.modelId` updated from `sonnet-5` to `sonnet-4-6`

---

## How to Request Gated Models

1. **AWS Sales**: https://aws.amazon.com/contact-us/sales-support/
2. **AWS Support**: Open a Bedrock model access case (Business/Enterprise support)
3. **Account team**: Request enablement from TAM or SA directly

## Re-verification Command

```bash
BODY=$(echo -n '{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}' | base64 -w0)
for model in us.anthropic.claude-opus-5 us.anthropic.claude-fable-5-1 us.anthropic.claude-sonnet-5; do
  aws bedrock-runtime invoke-model --region us-east-1 --model-id "$model" \
    --content-type application/json --accept application/json --body "$BODY" /tmp/test.json 2>&1 \
    | grep -q contentType && echo "OK     $model" || echo "DENIED $model"
done
```

## When Access is Granted

Update these files to use the preferred models:

| File | What to change |
|---|---|
| `Dockerfile` | ENV vars (lines 81-85) and Python defaults (lines 131-133) |
| `.env.example` | Commented model overrides |
| `entrypoint.sh` | Startup message (if Fable becomes available) |
| `openclaw-bedrock/scripts/bootstrap.sh` | `CLAUDE_SONNET_MODEL` variable |
| `openclaw-bedrock/scripts/openclaw-config.json.tpl` | `deepFallback.modelId` |
| `~/.claude/settings.json` | `env` block model overrides (per-container, not committed) |
