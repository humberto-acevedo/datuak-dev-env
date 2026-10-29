# WIF authentication investigation (2026-10-29)

Symptom: `make claude` launches Claude Code, which shows an interactive login
instead of authenticating through Workload Identity Federation (WIF).

## Root cause

Claude Code only uses WIF when these are set (or a profile is active):

- `ANTHROPIC_FEDERATION_RULE_ID` (`fdrl_...`)
- `ANTHROPIC_ORGANIZATION_ID`
- `ANTHROPIC_SERVICE_ACCOUNT_ID` (`svac_...`)
- `ANTHROPIC_IDENTITY_TOKEN_FILE` or `ANTHROPIC_IDENTITY_TOKEN`
- optional `ANTHROPIC_WORKSPACE_ID`

The repo does not pass any of them into the container. `workspace/Makefile`
`DEV_ENV` passes only AWS credentials, `AWS_REGION`, `AWS_ACCOUNT` and `AWS_ROLE_ARN`.

Other gaps:

- `AWS_ROLE_ARN` is not read by anything. Nothing calls `sts:AssumeRole` or
  `sts:GetWebIdentityToken`. `_run-with-creds` exports the SSO session credentials directly.
- `infra/lib/anthropic-wif-stack.ts` creates `anthropic-workload-identity`
  with only `bedrock:InvokeModel*`. It needs `sts:GetWebIdentityToken`.
- Account-level outbound web identity federation is not enabled anywhere in the repo.
- The identity token expires (15 min to 1 h) and is re-read on every exchange.
  A file written once at startup will fail later. Tokens with a `jti` are single-use.
- `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` shadow federation. Empty-string
  variables still occupy their precedence slot, so unset them rather than blanking them.
- `Dockerfile` sets `ANTHROPIC_MODEL` and the other model variables to Bedrock IDs
  (`us.anthropic.claude-*`). The first-party API probably needs `claude-*-5-5`. Not yet tested.
- `make wif-test` and `verify` only run `aws sts get-caller-identity`. They don't test WIF.
- `.env` sets `AWS_ACCOUNT`, but the Makefile derives `AWS_ROLE_ARN` from `ACCOUNT_ID`.
  They match today, but changing `.env` won't update the role ARN.

## Current state

- No Anthropic WIF resources exist yet: no federation issuer, service account, or rule,
  and no `fdrl_` / `svac_` / `wrkspc_` IDs. The Console Workload identity page has nothing to show.
- The user is an AWS Administrator and can see the **Connect workload** button, so Anthropic-side access looks fine.
- No commit touched Anthropic or AWS. The commits only changed local files. The repo never calls the Anthropic Console or API.
- The CDK only creates the `anthropic-workload-identity` IAM role in AWS. `infra/cdk.out` shows a synth on Oct 28, but the deploy is unconfirmed.
- Nothing in the repo creates WIF resources programmatically. The Console wizard is the normal path. Anthropic's Admin API is the programmatic alternative, but nothing here uses it.

## Next steps (run on the iMac host)

1. Confirm the CDK deploy:
   `aws cloudformation describe-stacks --stack-name AnthropicWIFStack --profile AdministratorAccess-539247495490 --query 'Stacks[0].StackStatus'`
2. Enable outbound web identity federation:
   `python3 -c "import boto3; boto3.client('iam').enable_outbound_web_identity_federation()"`
   (or IAM → Account settings).
3. Get the issuer URL (`https://<uuid>.tokens.sts.global.api.aws`):
   `python3 -c "import boto3; print(boto3.client('iam').get_outbound_web_identity_federation_info())"`
4. Add `sts:GetWebIdentityToken` to the role the container uses. Update `infra/lib/anthropic-wif-stack.ts` and redeploy.
5. Console → Workload identity → **Connect workload** → AWS, using the issuer URL from step 3.
   Match `sub` to the chosen role ARN and set the audience to `https://api.anthropic.com`.
   Record the `fdrl_`, `svac_`, and `wrkspc_` IDs. The org ID is under Settings → Organization.
6. Repo changes:
   - Pass the `ANTHROPIC_*` federation variables through `DEV_ENV` in `workspace/Makefile`.
   - Mint the identity token before each exchange.
   - Switch model IDs in `workspace/Dockerfile` to first-party names.
   - Make `wif-test` perform a real exchange.

Decision (2026-10-29): use the SSO permission-set role directly. The federation rule
matches `sub = arn:aws:iam::539247495490:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_3016282ce18041c3`.
If the permission set is re-provisioned, the suffix changes and the rule must be updated.
As a result, `AnthropicWIFStack` (the `anthropic-workload-identity` role) was destroyed
and `infra/`, `AWS_ROLE_ARN`, and the `wif-deploy`/`wif-describe` targets were removed.

## Outcome (2026-10-29)

- `make wif-setup` (`workspace/scripts/setup-anthropic-wif.sh`) enabled outbound federation.
  Issuer: `https://a1d4dbc7-4bb2-4db5-b470-14392fc227ce.tokens.sts.global.api.aws`.
  Token minting can fail for about a minute right after enabling; the script retries.
- The federation IDs live in `workspace/.env`. The Makefile passes them to the container.
- `workspace/scripts/with-wif-token.sh` mints a token on the host every 60 s into a per-run
  directory mounted at `/run/anthropic-wif`. Claude Code reads it through `ANTHROPIC_IDENTITY_TOKEN_FILE`.
- The Dockerfile uses first-party model names. `CLAUDE_CODE_USE_BEDROCK=1` makes the entrypoint
  add the `us.anthropic.` prefix. Bedrock invocation is still blocked for the account (403).
- Claude Code reads `ANTHROPIC_MODEL` and `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`.
  `ANTHROPIC_LARGE_MODEL` and `ANTHROPIC_ULTRA_FAST_MODEL` were never read.
- The host `~/.claude/settings.json` is mounted into the container. Its `env` block overrides
  `docker run -e`, so a `CLAUDE_CODE_USE_BEDROCK` key there defeats the Makefile switch.

## Verification checklist

- [x] An STS web identity token for `https://api.anthropic.com` can be minted on the host (boto3; the AWS CLI 2.27 has no command for it)
- [x] The token exchange works (done by the Python SDK's `WorkloadIdentityCredentials`; the access token itself was not inspected)
- [x] Inside the container, `claude -p` answers without a login prompt (`make wif-test`)
- [x] A messages request succeeds with a first-party model ID (`claude-sonnet-5-5` from the SDK, `claude-haiku-5-5` from Claude Code)
- [ ] An interactive `make claude` session launches with no login prompt (same launch path as `wif-test`, not yet tried interactively)
