#!/bin/bash
#
# Multi-host Claude context sync setup (Phase 1: One-way S3 master)
#
# This script sets up AWS S3 as a central repository for Claude context
# across Mac + AWS workspace hosts. Context automatically syncs:
#   - Before session start: download latest from S3
#   - After session end: upload changes to S3
#
# Usage: ./scripts/sync-setup.sh [AWS_PROFILE]
#

set -e

AWS_PROFILE="${1:-${AWS_PROFILE:-default}}"
REGION="${AWS_REGION:-us-east-1}"

echo "=== Claude Multi-Host Context Sync Setup (Phase 1) ==="
echo ""

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --query Account --output text)
if [ -z "$ACCOUNT_ID" ]; then
  echo "❌ Failed to get AWS account ID. Check AWS credentials."
  exit 1
fi

BUCKET="claude-context-${ACCOUNT_ID}"

echo "Configuration:"
echo "  Account ID:    ${ACCOUNT_ID}"
echo "  Bucket:        ${BUCKET}"
echo "  Region:        ${REGION}"
echo "  Profile:       ${AWS_PROFILE}"
echo "  Context path:  s3://${BUCKET}/.claude/ (shared across all hosts)"
echo ""

# Step 1: Create S3 bucket
echo "Step 1️⃣  Creating S3 bucket..."
if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "  ✅ Bucket already exists: ${BUCKET}"
else
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --profile "${AWS_PROFILE}" 2>/dev/null
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}" \
      --profile "${AWS_PROFILE}" 2>/dev/null
  fi
  echo "  ✅ Created bucket: ${BUCKET}"
fi

# Step 2: Enable versioning (for rollback/recovery)
echo ""
echo "Step 2️⃣  Enabling versioning (for history/rollback)..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled \
  --region "${REGION}" \
  --profile "${AWS_PROFILE}"
echo "  ✅ Versioning enabled"

# Step 3: Enable encryption
echo ""
echo "Step 3️⃣  Enabling AES-256 encryption..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' \
  --region "${REGION}" \
  --profile "${AWS_PROFILE}"
echo "  ✅ Encryption enabled (AES-256)"

# Step 4: Block public access
echo ""
echo "Step 4️⃣  Blocking public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --region "${REGION}" \
  --profile "${AWS_PROFILE}"
echo "  ✅ Public access blocked"

# Step 5: Add bucket tags
echo ""
echo "Step 5️⃣  Adding tags..."
aws s3api put-bucket-tagging \
  --bucket "${BUCKET}" \
  --tagging 'TagSet=[
    {Key=Purpose,Value=claude-context-sync},
    {Key=CreatedBy,Value=datuak-dev-env},
    {Key=Account,Value='${ACCOUNT_ID}'}
  ]' \
  --region "${REGION}" \
  --profile "${AWS_PROFILE}"
echo "  ✅ Tags added"

# Step 6: Test access
echo ""
echo "Step 6️⃣  Testing S3 access..."
TEST_FILE="/tmp/claude-sync-test-$$"
TEST_KEY="sync-test-$(date +%s).txt"

echo "test from $(hostname -s) at $(date)" > "${TEST_FILE}"

if aws s3 cp "${TEST_FILE}" "s3://${BUCKET}/${TEST_KEY}" \
  --region "${REGION}" \
  --profile "${AWS_PROFILE}" \
  --sse AES256 >/dev/null 2>&1; then
  echo "  ✅ Write access verified"

  if aws s3 cp "s3://${BUCKET}/${TEST_KEY}" /tmp/claude-sync-test-read-$$ \
    --region "${REGION}" \
    --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
    echo "  ✅ Read access verified"
  else
    echo "  ❌ Read access failed"
    exit 1
  fi

  # Cleanup
  aws s3 rm "s3://${BUCKET}/${TEST_KEY}" \
    --region "${REGION}" \
    --profile "${AWS_PROFILE}" >/dev/null 2>&1
  rm -f "${TEST_FILE}" /tmp/claude-sync-test-read-$$
else
  echo "  ❌ Write access failed"
  exit 1
fi

# Step 7: Display summary
echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo ""
echo "1️⃣  Update Makefile with bucket name:"
echo "   CLAUDE_CONTEXT_BUCKET=${BUCKET}"
echo ""
echo "2️⃣  On each host, sync down existing context:"
echo "   make sync-from-s3"
echo ""
echo "3️⃣  Launch Claude (auto-syncs):"
echo "   make claude"
echo ""
echo "Monitor sync:"
echo "  make list-remote-contexts     List all synced contexts"
echo "  aws s3 ls s3://${BUCKET}/ --recursive"
echo ""
echo "Manual sync:"
echo "  make sync-to-s3               Upload ~/.claude to S3"
echo "  make sync-from-s3             Download latest from S3"
echo ""
echo "Recovery (versioning enabled):"
echo "  aws s3api list-object-versions --bucket ${BUCKET}"
echo "  aws s3api get-object --bucket ${BUCKET} --key <key> --version-id <vid> <local-file>"
echo ""
