#!/bin/bash
#
# Configure the AWS side of Anthropic Workload Identity Federation (WIF).
#
# Automates:
#   1. AWS SSO session check
#   2. CDK deploy of AnthropicWIFStack (role + sts:GetWebIdentityToken)
#   3. Account-level outbound web identity federation (enable + issuer URL)
#   4. Role permission check and a test token mint
#
# Prints the steps that need the Anthropic Console, which has no automation here.
# Safe to re-run: each step checks current state before changing anything.
#
# Usage: ./scripts/setup-anthropic-wif.sh [--check]
#   --check  report current state only; change nothing
#
# Overrides (same defaults as the Makefile): ACCOUNT_ID, AWS_PROFILE, REGION

set -euo pipefail

ACCOUNT_ID="${ACCOUNT_ID:-539247495490}"
AWS_PROFILE="${AWS_PROFILE:-AdministratorAccess-${ACCOUNT_ID}}"
REGION="${REGION:-us-east-1}"
STACK_NAME="AnthropicWIFStack"
ROLE_NAME="anthropic-workload-identity"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
ANTHROPIC_AUDIENCE="https://api.anthropic.com"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/../../infra" && pwd)"

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

# 2. CDK stack ----------------------------------------------------------------
step "2. CDK stack $STACK_NAME"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_DEPLOYED")
echo "   current status: $STACK_STATUS"
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "   (check only) would run: npx cdk deploy $STACK_NAME"
else
  if [ ! -d "$INFRA_DIR/node_modules" ]; then
    echo "   installing CDK dependencies in $INFRA_DIR ..."
    (cd "$INFRA_DIR" && npm ci --silent)
  fi
  (cd "$INFRA_DIR" && npx cdk deploy "$STACK_NAME" --require-approval never)
  echo "   ✅ Stack deployed"
fi

# 3. Outbound web identity federation -----------------------------------------
step "3. Outbound web identity federation"
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

# 4. Role permission and test token -------------------------------------------
step "4. Role permission and test token"
if [ -z "$ISSUER" ]; then
  echo "   skipped: federation is not enabled yet (run without --check)"
else
  python3 -I - "$ROLE_NAME" "$ANTHROPIC_AUDIENCE" <<'PY' || echo "   ⚠️  Token check did not pass; see the message above. Continuing."
import base64
import json
import sys
import time
import boto3
from botocore.exceptions import ClientError

role, audience = sys.argv[1], sys.argv[2]
iam = boto3.client("iam")

granted = False
for name in iam.list_role_policies(RoleName=role)["PolicyNames"]:
    doc = iam.get_role_policy(RoleName=role, PolicyName=name)["PolicyDocument"]
    statements = doc["Statement"] if isinstance(doc["Statement"], list) else [doc["Statement"]]
    for s in statements:
        actions = s.get("Action", [])
        actions = [actions] if isinstance(actions, str) else actions
        if s.get("Effect") == "Allow" and "sts:GetWebIdentityToken" in actions:
            granted = True

if granted:
    print("   ✅ Role grants sts:GetWebIdentityToken")
else:
    print("   ❌ Role is missing sts:GetWebIdentityToken (check the CDK deploy)")
    sys.exit(1)

sts = boto3.client("sts")
# A freshly enabled account can take a short while before token minting works
token = None
for attempt in range(1, 11):
    try:
        token = sts.get_web_identity_token(
            Audience=[audience], SigningAlgorithm="ES384", DurationSeconds=300
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

# 5. Anthropic Console --------------------------------------------------------
step "5. Anthropic Console"
if [ -n "${ANTHROPIC_ORGANIZATION_ID:-}" ] && [ -n "${ANTHROPIC_FEDERATION_RULE_ID:-}" ] \
   && [ -n "${ANTHROPIC_SERVICE_ACCOUNT_ID:-}" ]; then
  echo "   ✅ ANTHROPIC_* federation IDs are set in the environment; nothing to do"
else
  echo "   The Anthropic side is not automated here (the Admin API route is not wired up)."
  manual "Console → Workload identity → Connect workload → AWS"
  echo "       Issuer URL : ${ISSUER:-<not enabled yet; run this script without --check>}"
  echo "       Audience   : $ANTHROPIC_AUDIENCE"
  echo "       Role ARN   : the token subject printed in step 4 (your SSO role)"
  manual "Record the IDs: fdrl_... (federation rule), svac_... (service account),"
  echo "       wrkspc_... (optional workspace), and the org ID (Settings → Organization)"
  manual "Add them to workspace/.env, then run 'make wif-setup' again to confirm:"
  echo "       ANTHROPIC_ORGANIZATION_ID=<org id>"
  echo "       ANTHROPIC_FEDERATION_RULE_ID=fdrl_..."
  echo "       ANTHROPIC_SERVICE_ACCOUNT_ID=svac_..."
  echo "       ANTHROPIC_WORKSPACE_ID=wrkspc_...   # optional"
  manual "Repo follow-up (not done by this script): pass these through DEV_ENV in"
  echo "       workspace/Makefile, mint the identity token before each exchange,"
  echo "       and switch the Dockerfile model IDs to first-party names."
fi

echo
if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "Check complete. No changes made."
else
  echo "AWS-side setup complete."
fi
