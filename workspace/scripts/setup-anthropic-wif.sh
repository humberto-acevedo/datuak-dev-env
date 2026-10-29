#!/bin/bash
#
# Configure the AWS side of Anthropic Workload Identity Federation (WIF).
#
# Automates:
#   1. AWS SSO session check
#   2. Account-level outbound web identity federation (enable + issuer URL)
#   3. A test token mint, printing the subject the Console rule must match
#
# Tokens are minted with the SSO role's own credentials, so no extra IAM role
# is needed. Prints the steps that need the Anthropic Console, which has no
# automation here. Safe to re-run: each step checks current state first.
#
# Usage: ./scripts/setup-anthropic-wif.sh [--check]
#   --check  report current state only; change nothing
#
# Overrides (same defaults as the Makefile): ACCOUNT_ID, AWS_PROFILE, REGION

set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:-539247495490}"
AWS_PROFILE="${AWS_PROFILE:-AdministratorAccess-${ACCOUNT_ID}}"
REGION="${REGION:-us-east-1}"
ANTHROPIC_AUDIENCE="https://api.anthropic.com"

CHECK_ONLY=0
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  "") ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

export AWS_PROFILE AWS_REGION="$REGION"

step() { echo; echo "▶ $*"; }
manual() { echo "   ➜ MANUAL: $*"; }

# 1. AWS session --------------------------------------------------------------
step "1. AWS session (profile $AWS_PROFILE)"
if ! CALLER_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
  echo "   ❌ No valid AWS session."
  manual "make sso-login   (or: aws sso login --profile $AWS_PROFILE), then re-run this script"
  exit 1
fi
if [ "$CALLER_ACCOUNT" != "$ACCOUNT_ID" ]; then
  echo "   ❌ Profile $AWS_PROFILE is in account $CALLER_ACCOUNT, expected $ACCOUNT_ID"
  manual "Set AWS_PROFILE to a profile for account $ACCOUNT_ID"
  exit 1
fi
echo "   ✅ Signed in to account $ACCOUNT_ID"

# 2. Outbound web identity federation -----------------------------------------
step "2. Outbound web identity federation"
FED_MODE=apply
[ "$CHECK_ONLY" -eq 1 ] && FED_MODE=check
ISSUER=$(python3 -I - "$FED_MODE" <<'PY'
import sys
import boto3
from botocore.exceptions import ClientError

mode = sys.argv[1]
iam = boto3.client("iam")

def issuer_or_none():
    try:
        return iam.get_outbound_web_identity_federation_info()["IssuerIdentifier"]
    except ClientError as e:
        if e.response["Error"]["Code"] in ("FeatureDisabled", "FeatureDisabledException"):
            return None
        raise

issuer = issuer_or_none()
if issuer is None and mode == "apply":
    issuer = iam.enable_outbound_web_identity_federation()["IssuerIdentifier"]
    print("   enabled outbound federation for the account", file=sys.stderr)
print(issuer or "")
PY
)
if [ -n "$ISSUER" ]; then
  echo "   ✅ Enabled. Issuer: $ISSUER"
elif [ "$CHECK_ONLY" -eq 1 ]; then
  echo "   ⚠️  Disabled (would enable)"
else
  echo "   ❌ Could not enable outbound federation"
  exit 1
fi

# 3. Test token ---------------------------------------------------------------
step "3. Test token"
if [ -z "$ISSUER" ]; then
  echo "   skipped: federation is not enabled yet (run without --check)"
else
  python3 -I - "$ANTHROPIC_AUDIENCE" <<'PY' || echo "   ⚠️  Token check did not pass; see the message above. Continuing."
import base64
import json
import sys
import time
import boto3
from botocore.exceptions import ClientError

audience = sys.argv[1]
sts = boto3.client("sts")

# A freshly enabled account can take a short while before token minting works
token = None
for attempt in range(1, 11):
    try:
        token = sts.get_web_identity_token(
            Audience=[audience], SigningAlgorithm="RS256", DurationSeconds=300
        )["WebIdentityToken"]
        break
    except ClientError as e:
        if e.response["Error"]["Code"] != "OutboundWebIdentityFederationDisabledException" or attempt == 10:
            raise
        print(f"   waiting for federation to propagate (attempt {attempt}/10) ...")
        time.sleep(15)
print(f"   ✅ Minted a test token for {audience} ({len(token)} chars, not displayed)")
payload = token.split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(f"   token subject: {claims['sub']}")
print("   (the Console federation rule must match this subject)")
PY
fi

# 4. Anthropic Console --------------------------------------------------------
step "4. Anthropic Console"
if [ -n "${ANTHROPIC_ORGANIZATION_ID:-}" ] && [ -n "${ANTHROPIC_FEDERATION_RULE_ID:-}" ] \
   && [ -n "${ANTHROPIC_SERVICE_ACCOUNT_ID:-}" ]; then
  echo "   ✅ ANTHROPIC_* federation IDs are set; run 'make wif-test' to check Claude Code"
else
  echo "   The Anthropic side is not automated here (the Admin API route is not wired up)."
  manual "Console → Workload identity → Connect workload → AWS"
  echo "       Issuer URL : ${ISSUER:-<not enabled yet; run this script without --check>}"
  echo "       Audience   : $ANTHROPIC_AUDIENCE"
  echo "       Role ARN   : the token subject printed in step 3 (your SSO role)"
  manual "Record the IDs: fdrl_... (federation rule), svac_... (service account),"
  echo "       wrkspc_... (optional workspace), and the org ID (Settings → Organization)"
  manual "Add them to workspace/.env, then run 'make wif-test':"
  echo "       ANTHROPIC_ORGANIZATION_ID=<org id>"
  echo "       ANTHROPIC_FEDERATION_RULE_ID=fdrl_..."
  echo "       ANTHROPIC_SERVICE_ACCOUNT_ID=svac_..."
  echo "       ANTHROPIC_WORKSPACE_ID=wrkspc_...   # optional"
fi

echo
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Check complete. No changes made."
else
  echo "AWS-side setup complete."
fi
