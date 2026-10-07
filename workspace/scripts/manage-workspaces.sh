#!/bin/bash
# manage-workspaces.sh
# List, start, or stop WorkSpaces in the current AWS account/region.
# Usage: ./manage-workspaces.sh <list|start|stop> [--user <username>] [--region <region>] [--profile <profile>] [--dry-run]

set -euo pipefail

ACTION=""
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
PROFILE=""
DRY_RUN=false
TARGET_USER=""

usage() {
  cat <<EOF
Usage: $0 <list|start|stop> [OPTIONS]

Actions:
  list              List all WorkSpaces with their current state
  start             Start all WorkSpaces (or a specific one with --user)
  stop              Stop all WorkSpaces (or a specific one with --user)

Options:
  --user <username> Target a specific WorkSpace by username
  --region <region> AWS region (default: us-west-2)
  --profile <name>  AWS CLI profile (default: default)
  --dry-run         Preview actions without executing

Examples:
  $0 list
  $0 start --user humberto.acevedo
  $0 stop --dry-run
  $0 stop --user humberto.acevedo --region us-west-2
EOF
  exit 1
}

# First positional arg is the action
if [[ $# -gt 0 && ( "$1" == "list" || "$1" == "start" || "$1" == "stop" ) ]]; then
  ACTION="$1"
  shift
else
  echo "Error: first argument must be 'list', 'start', or 'stop'."
  usage
fi

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      TARGET_USER="$2"
      shift 2
      ;;
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
      usage
      ;;
  esac
done

# Build base AWS CLI args array (array form handles spaces in profile names)
AWS_ARGS=(--region "$REGION")
if [[ -n "$PROFILE" ]]; then
  AWS_ARGS+=(--profile "$PROFILE")
fi

# ─── Helpers ────────────────────────────────────────────────────────────────

fetch_workspaces() {
  aws workspaces describe-workspaces "${AWS_ARGS[@]}" \
    --query 'Workspaces[*].{ID:WorkspaceId,User:UserName,State:State,Bundle:BundleId}' \
    --output json
}

print_table() {
  aws workspaces describe-workspaces "${AWS_ARGS[@]}" \
    --query 'Workspaces[*].{ID:WorkspaceId,User:UserName,State:State,Bundle:BundleId}' \
    --output table
}

# ─── List action ────────────────────────────────────────────────────────────

if [[ "$ACTION" == "list" ]]; then
  echo "=== WorkSpaces in $REGION ==="
  print_table
  exit 0
fi

# ─── Start / Stop actions ───────────────────────────────────────────────────

echo "=== Manage WorkSpaces Script ==="
echo "Action:  $ACTION"
echo "Region:  $REGION"
echo "Profile: ${PROFILE:-default}"
echo "Target:  ${TARGET_USER:-all}"
echo "Dry run: $DRY_RUN"
echo ""

# Fetch workspace data as JSON
echo "Fetching WorkSpaces..."
WS_JSON=$(fetch_workspaces)

if [[ -z "$WS_JSON" || "$WS_JSON" == "[]" ]]; then
  echo "No WorkSpaces found in region $REGION."
  exit 0
fi

# Filter by user if --user was specified
if [[ -n "$TARGET_USER" ]]; then
  WS_JSON=$(echo "$WS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
filtered = [w for w in data if w['User'].lower() == '${TARGET_USER}'.lower()]
print(json.dumps(filtered))
")
  if [[ -z "$WS_JSON" || "$WS_JSON" == "[]" ]]; then
    echo "No WorkSpace found for user '$TARGET_USER' in region $REGION."
    exit 1
  fi
fi

# Extract IDs and display table
WORKSPACE_IDS=$(echo "$WS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('\n'.join(w['ID'] for w in data))
")

echo "Found WorkSpaces:"
echo "$WS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
col = '{:<16} {:<15} {:<12} {:<20}'
sep = '-' * 67
print(sep)
print(col.format('Bundle', 'ID', 'State', 'User'))
print(sep)
for w in data:
    print(col.format(w['Bundle'], w['ID'], w['State'], w['User']))
print(sep)
"
echo ""

if $DRY_RUN; then
  echo "[DRY RUN] Would $ACTION the following WorkSpace IDs:"
  echo "$WORKSPACE_IDS"
  exit 0
fi

# Confirm before acting
ACTION_LABEL="$(echo "$ACTION" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
read -rp "$ACTION_LABEL WorkSpace(s) listed above? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# Process in batches of 25 (API limit)
echo ""
echo "Sending $ACTION requests..."
BATCH=()
COUNT=0

while IFS= read -r WS_ID; do
  [[ -z "$WS_ID" ]] && continue
  BATCH+=("WorkspaceId=$WS_ID")
  COUNT=$((COUNT + 1))

  if [[ ${#BATCH[@]} -eq 25 ]]; then
    aws workspaces "${ACTION}-workspaces" \
      "${AWS_ARGS[@]}" \
      "--${ACTION}-workspace-requests" "${BATCH[@]}"
    echo "  Sent $ACTION for batch of 25 (total so far: $COUNT)"
    BATCH=()
  fi
done <<< "$WORKSPACE_IDS"

# Send any remaining
if [[ ${#BATCH[@]} -gt 0 ]]; then
  aws workspaces "${ACTION}-workspaces" \
    "${AWS_ARGS[@]}" \
    "--${ACTION}-workspace-requests" "${BATCH[@]}"
  echo "  Sent $ACTION for remaining ${#BATCH[@]} workspace(s) (total: $COUNT)"
fi

echo ""
echo "Done. $ACTION_LABEL requests sent for $COUNT WorkSpace(s)."

if [[ "$ACTION" == "stop" ]]; then
  echo "WorkSpaces will transition: AVAILABLE → STOPPING → STOPPED"
  echo "Note: AlwaysOn bundles cannot be stopped and will return an error."
else
  echo "WorkSpaces will transition: STOPPED → STARTING → AVAILABLE"
  echo "Note: WorkSpaces already running will return an error (harmless)."
fi
