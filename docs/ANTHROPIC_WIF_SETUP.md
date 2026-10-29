# Anthropic Workload Identity Federation (WIF)

Claude Code in the container authenticates to the Anthropic API with short-lived
AWS STS tokens. No Anthropic API key is stored anywhere.

## How it works

```
Host (make claude)                          Container
──────────────────                          ─────────
SSO profile ─► sts:GetWebIdentityToken      Claude Code
               (aud https://api.anthropic.com)   │ reads ANTHROPIC_IDENTITY_TOKEN_FILE
               every 60 s ─► token file ─────────┤ on every exchange
                                                 ▼
                              Anthropic API: token + federation rule ─► access token
```

- The token is minted with the SSO role's own credentials. Its `sub` claim is the
  SSO role ARN, and the Anthropic federation rule matches on it.
- `workspace/scripts/with-wif-token.sh` re-mints the token every 60 seconds into a
  per-run directory mounted at `/run/anthropic-wif`. Tokens are short-lived and
  re-read on every exchange, so a token written once would expire.
- The Makefile passes `ANTHROPIC_ORGANIZATION_ID`, `ANTHROPIC_FEDERATION_RULE_ID`,
  `ANTHROPIC_SERVICE_ACCOUNT_ID`, `ANTHROPIC_WORKSPACE_ID` (from `workspace/.env`)
  and `ANTHROPIC_IDENTITY_TOKEN_FILE` into the container.

## One-time setup

1. AWS side: `make wif-setup` (`ARGS=--check` reports state without changes).
   It enables account-level outbound web identity federation, prints the issuer
   URL, mints a test token, and prints the token subject.
2. Anthropic Console → Workload identity → **Connect workload** → AWS:
   - Issuer URL: from step 1
   - Audience: `https://api.anthropic.com`
   - Role ARN: the token subject from step 1
   - Service account: create one; note its `svac_` ID
3. Add the IDs to `workspace/.env` (see `.env.example`).
4. `make wif-test` runs `claude -p` in the container and must answer without a login prompt.

## Providers

`CLAUDE_CODE_USE_BEDROCK=0` (default) uses the Anthropic API through WIF.
`CLAUDE_CODE_USE_BEDROCK=1` (in `.env`, or `make claude CLAUDE_CODE_USE_BEDROCK=1`)
uses Bedrock with the SSO credentials; the entrypoint turns the model names into
`us.anthropic.*` inference profile IDs.

The host `~/.claude/settings.json` is mounted into the container, and its `env`
block overrides `docker run -e`. Keep `CLAUDE_CODE_USE_BEDROCK` out of it, or the
Makefile switch has no effect.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `Not logged in · Please run /login` | IDs missing from `.env`, or a `CLAUDE_CODE_USE_BEDROCK` key in host settings |
| `Could not mint an Anthropic WIF identity token` | `make sso-login`; then `make wif-setup ARGS=--check` |
| `OutboundWebIdentityFederationDisabledException` right after enabling | Wait about a minute; `wif-setup` retries automatically |
| Token exchange rejected | The rule's Role ARN must equal the token subject; it changes if the SSO permission set is re-provisioned |

Background and decisions: [WIF_INVESTIGATION.md](WIF_INVESTIGATION.md).
