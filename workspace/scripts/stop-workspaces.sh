#!/bin/bash
# stop-workspaces.sh
# Stops all WorkSpaces in the current AWS account/region.
# Usage: ./stop-workspaces.sh [--region <region>] [--profile <profile>] [--dry-run]

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROFILE=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--region <region>] [--profile <profile>] [--dry-run]"
      exit 1
      ;;
  esac
done

# Build base AWS CLI args
AWS_ARGS="--region $REGION"
if [[ -n "$PROFILE" ]]; then
  AWS_ARGS="$AWS_ARGS --profile $PROFILE"
fi

echo "=== Stop WorkSpaces Script ==="
echo "Region:  $REGION"
echo "Profile: ${PROFILE:-default}"
echo "Dry run: $DRY_RUN"
echo ""

# Fetch all workspace IDs with pagination
echo "Fetching WorkSpaces..."
WORKSPACE_IDS=$(aws workspaces describe-workspaces \
  $AWS_ARGS \
  --query 'Workspaces[*].WorkspaceId' \
  --output text)

if [[ -z "$WORKSPACE_IDS" ]]; then
  echo "No WorkSpaces found in region $REGION."
  exit 0
fi

# Display found workspaces
echo "Found WorkSpaces:"
aws workspaces describe-workspaces \
  $AWS_ARGS \
  --query 'Workspaces[*].{ID:WorkspaceId,User:UserName,State:State,Bundle:BundleId}' \
  --output table

echo ""

if $DRY_RUN; then
  echo "[DRY RUN] Would stop the following WorkSpace IDs:"
  echo "$WORKSPACE_IDS" | tr '\t' '\n'
  exit 0
fi

# Confirm before stopping
read -rp "Stop all WorkSpaces listed above? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# Stop workspaces in batches of 25 (API limit)
echo ""
echo "Sending stop requests..."
BATCH=()
COUNT=0

for WS_ID in $WORKSPACE_IDS; do
  BATCH+=("WorkspaceId=$WS_ID")
  COUNT=$((COUNT + 1))

  if [[ ${#BATCH[@]} -eq 25 ]]; then
    aws workspaces stop-workspaces \
      $AWS_ARGS \
      --stop-workspace-requests "${BATCH[@]}"
    echo "  Sent stop for batch of 25 (total so far: $COUNT)"
    BATCH=()
  fi
done

# Send any remaining
if [[ ${#BATCH[@]} -gt 0 ]]; then
  aws workspaces stop-workspaces \
    $AWS_ARGS \
    --stop-workspace-requests "${BATCH[@]}"
  echo "  Sent stop for remaining ${#BATCH[@]} workspace(s) (total: $COUNT)"
fi

echo ""
echo "Done. Stop requests sent for $COUNT WorkSpace(s)."
echo "WorkSpaces will transition: AVAILABLE → STOPPING → STOPPED"
echo "Note: AlwaysOn bundles cannot be stopped and will return an error."
