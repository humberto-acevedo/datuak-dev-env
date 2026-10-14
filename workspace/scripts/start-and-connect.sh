#!/bin/bash
# start-and-connect.sh
# Start an AWS WorkSpace and connect to it via SSM Session Manager.
#
# Usage:
#   ./start-and-connect.sh [--workspace-id <id>] [--profile <name>] [--region <region>] [--timeout <seconds>]
#
# Requirements:
#   - AWS CLI v2
#   - Session Manager plugin: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
#   - Profile must have workspaces:StartWorkspaces + ssm:StartSession permissions

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────

WORKSPACE_ID="ws-ccwyrjx09"
PROFILE="AdministratorAccess-539247495490"
REGION="us-west-2"
TIMEOUT=600          # seconds to wait for AVAILABLE state (default 10 min)
POLL_INTERVAL=15
SSM_WAIT_TIMEOUT=300 # seconds to wait for SSM registration after AVAILABLE (default 5 min)
SSM_POLL_INTERVAL=15

# ─── Argument parsing ────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Start an AWS WorkSpace and connect via SSM Session Manager.

Options:
  --workspace-id <id>    WorkSpace ID (default: $WORKSPACE_ID)
  --profile <name>       AWS CLI profile (default: $PROFILE)
  --region <region>      AWS region (default: $REGION)
  --timeout <seconds>    Max seconds to wait for AVAILABLE state (default: $TIMEOUT)
  --ssm-timeout <secs>   Max seconds to wait for SSM registration after AVAILABLE (default: $SSM_WAIT_TIMEOUT)
  --user-name            User name
  --help                 Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --workspace-id ws-abc123 --profile my-profile
  $(basename "$0") --ssm-timeout 60   # fail fast if SSM doesn't register within 1 min
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-id) WORKSPACE_ID="$2";    shift 2 ;;
    --profile)      PROFILE="$2";         shift 2 ;;
    --region)       REGION="$2";          shift 2 ;;
    --timeout)      TIMEOUT="$2";         shift 2 ;;
    --ssm-timeout)  SSM_WAIT_TIMEOUT="$2"; shift 2 ;;
    --help)         usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

AWS_ARGS=(--region "$REGION" --profile "$PROFILE")

# ─── Helper: check SSM plugin installation ──────────────────────────────────

check_ssm_plugin() {
  if ! command -v session-manager-plugin &> /dev/null; then
    echo "ERROR: AWS Session Manager plugin is not installed."
    echo ""
    echo "The plugin is required to connect via SSM but should not be committed to the repository."
    echo ""
    echo "To install:"
    echo "  macOS (Homebrew):  brew install --cask session-manager-plugin"
    echo "  macOS (manual):    https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-macos"
    echo "  Linux:             https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-linux"
    echo "  Windows:           https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html#install-plugin-windows"
    echo ""
    exit 1
  fi
}

# ─── Helper: get current workspace state ─────────────────────────────────────

get_state() {
  aws workspaces describe-workspaces \
    "${AWS_ARGS[@]}" \
    --workspace-ids "$WORKSPACE_ID" \
    --query 'Workspaces[0].State' \
    --output text 2>/dev/null || echo "UNKNOWN"
}

get_workspace_info() {
  aws workspaces describe-workspaces \
    "${AWS_ARGS[@]}" \
    --workspace-ids "$WORKSPACE_ID" \
    --query 'Workspaces[0].{ID:WorkspaceId,User:UserName,State:State,IP:IpAddress,Computer:ComputerName}' \
    --output table 2>/dev/null
}

# ─── Helper: find the SSM-managed instance for this workspace ─────────────────
# WorkSpaces registers as an SSM managed instance. The instance's ComputerName
# matches the workspace ComputerName or we can find it by the workspace IP tag.
#
# Matching strategy (in order):
#   1. Exact match via SSM filter (fast path)
#   2. Case-insensitive partial match across all SSM instances (handles domain
#      suffixes like "U-ABC123.CORP" and lowercase variants)
#   3. Retry loop: poll SSM for up to SSM_WAIT_TIMEOUT seconds in case the
#      agent is still starting up after the workspace becomes AVAILABLE
#   4. Manual selection from the full instance list

_try_match_ssm_instance() {
  # Returns instance ID if found, empty string otherwise.
  # $1 = computer_name  $2 = computer_name_lower
  local computer_name="$1"
  local computer_name_lower="$2"
  local instance_id

  # Exact match via SSM ComputerName filter
  instance_id=$(aws ssm describe-instance-information \
    "${AWS_ARGS[@]}" \
    --filters "Key=ComputerName,Values=${computer_name}" \
    --query 'InstanceInformationList[0].InstanceId' \
    --output text 2>/dev/null)

  if [[ -n "$instance_id" && "$instance_id" != "None" ]]; then
    echo "$instance_id"
    return
  fi

  # Case-insensitive partial match across all instances
  local all_instances
  all_instances=$(aws ssm describe-instance-information \
    "${AWS_ARGS[@]}" \
    --query 'InstanceInformationList[*].{id:InstanceId,name:ComputerName}' \
    --output json 2>/dev/null)

  instance_id=$(echo "$all_instances" | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
target = '$computer_name_lower'
for item in data:
    name = (item.get('name') or '').lower()
    if name == target or name.startswith(target + '.') or target.startswith(name + '.'):
        print(item['id'])
        sys.exit(0)
" 2>/dev/null)

  if [[ -n "$instance_id" && "$instance_id" != "None" ]]; then
    echo "$instance_id"
  fi
}

find_ssm_instance() {
  local computer_name
  computer_name=$(aws workspaces describe-workspaces \
    "${AWS_ARGS[@]}" \
    --workspace-ids "$WORKSPACE_ID" \
    --query 'Workspaces[0].ComputerName' \
    --output text 2>/dev/null)

  local computer_name_lower
  computer_name_lower=$(echo "$computer_name" | tr '[:upper:]' '[:lower:]')

  echo "  Looking for SSM instance with computer name: $computer_name" >&2

  # ── Step 1 & 2: Try immediate match (exact + case-insensitive) ────────────
  local instance_id
  instance_id=$(_try_match_ssm_instance "$computer_name" "$computer_name_lower")

  if [[ -n "$instance_id" ]]; then
    echo "$instance_id"
    return
  fi

  # ── Step 3: Polling loop — SSM agent may still be starting up ────────────
  # Ubuntu WorkSpaces can take 1–5 min after AVAILABLE for SSM to register.
  echo "" >&2
  echo "  Instance not yet in SSM. Polling for up to ${SSM_WAIT_TIMEOUT}s..." >&2
  echo "  (The SSM agent on the workspace may still be starting up)" >&2

  local elapsed=0
  local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spin_idx=0

  while [[ $elapsed -lt $SSM_WAIT_TIMEOUT ]]; do
    sleep "$SSM_POLL_INTERVAL"
    elapsed=$((elapsed + SSM_POLL_INTERVAL))

    printf "\r  %s  Waiting for SSM registration...  %ds / %ds" \
      "${spinner[$spin_idx]}" "$elapsed" "$SSM_WAIT_TIMEOUT" >&2
    spin_idx=$(( (spin_idx + 1) % ${#spinner[@]} ))

    instance_id=$(_try_match_ssm_instance "$computer_name" "$computer_name_lower")
    if [[ -n "$instance_id" ]]; then
      echo "" >&2
      echo "  ✓ SSM instance registered after ${elapsed}s." >&2
      echo "$instance_id"
      return
    fi
  done

  echo "" >&2
  echo "  SSM registration timed out after ${SSM_WAIT_TIMEOUT}s." >&2

  # ── Step 4: Manual fallback — list all online instances for user to pick ──
  echo "" >&2
  echo "  Could not auto-detect instance. Listing all online SSM managed instances:" >&2
  aws ssm describe-instance-information \
    "${AWS_ARGS[@]}" \
    --filters "Key=PingStatus,Values=Online" \
    --query 'InstanceInformationList[*].{ID:InstanceId,Name:ComputerName,IP:IPAddress,Platform:PlatformType}' \
    --output table 2>/dev/null >&2
  echo "" >&2
  echo -n "  Enter the SSM Instance ID to connect to (or press Enter to abort): " >&2
  read -r instance_id

  echo "$instance_id"
}

# ─── Main ────────────────────────────────────────────────────────────────────

echo "========================================"
echo "  WorkSpace Start & SSM Connect"
echo "========================================"
echo "  Workspace ID : $WORKSPACE_ID"
echo "  Profile      : $PROFILE"
echo "  Region       : $REGION"
echo "========================================"
echo ""

# Step 0: Verify SSM plugin is installed
echo "[0/4] Checking SSM plugin installation..."
check_ssm_plugin
echo "  ✓ Session Manager plugin is installed"
echo ""

# Step 1: Check current state
echo "[1/4] Checking workspace state..."
CURRENT_STATE=$(get_state)
echo "  Current state: $CURRENT_STATE"
echo ""

# Step 2: Start if needed
case "$CURRENT_STATE" in
  AVAILABLE)
    echo "[2/4] Workspace is already AVAILABLE. Skipping start."
    ;;
  STOPPED)
    echo "[2/4] Starting workspace $WORKSPACE_ID..."
    aws workspaces start-workspaces \
      "${AWS_ARGS[@]}" \
      --start-workspace-requests "WorkspaceId=$WORKSPACE_ID" \
      --query 'FailedRequests' \
      --output text

    echo "  Start request sent. Waiting for AVAILABLE state (timeout: ${TIMEOUT}s)..."
    ;;
  STARTING)
    echo "[2/4] Workspace is already STARTING. Waiting..."
    ;;
  STOPPING | REBOOTING | REBUILDING | MAINTENANCE)
    echo "  ERROR: Workspace is in '$CURRENT_STATE' state. Cannot start right now."
    echo "  Please wait for the current operation to complete and try again."
    exit 1
    ;;
  PENDING)
    echo "[2/4] Workspace is PENDING (first boot). Waiting..."
    ;;
  *)
    echo "  WARNING: Unexpected state '$CURRENT_STATE'. Attempting to start anyway..."
    aws workspaces start-workspaces \
      "${AWS_ARGS[@]}" \
      --start-workspace-requests "WorkspaceId=$WORKSPACE_ID" \
      --output text || true
    ;;
esac

# Step 3: Wait for AVAILABLE
echo ""
echo "[3/4] Waiting for workspace to become AVAILABLE..."
ELAPSED=0
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPIN_IDX=0

while true; do
  STATE=$(get_state)

  if [[ "$STATE" == "AVAILABLE" ]]; then
    echo ""
    echo "  ✓ Workspace is AVAILABLE"
    break
  fi

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo ""
    echo "  ERROR: Timed out after ${TIMEOUT}s. Current state: $STATE"
    echo "  You can check status with:"
    echo "    aws workspaces describe-workspaces --workspace-ids $WORKSPACE_ID --profile $PROFILE --region $REGION"
    exit 1
  fi

  printf "\r  %s  State: %-15s  Elapsed: %ds" "${SPINNER[$SPIN_IDX]}" "$STATE" "$ELAPSED"
  SPIN_IDX=$(( (SPIN_IDX + 1) % ${#SPINNER[@]} ))
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

echo ""
get_workspace_info
echo ""

# Step 4: Connect via SSM
echo "[4/4] Finding SSM managed instance for this workspace..."
INSTANCE_ID=$(find_ssm_instance)

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  echo ""
  echo "  ERROR: No SSM instance ID provided. Cannot connect."
  echo ""
  echo "  Troubleshooting tips:"
  echo "  - Ensure the SSM agent is running on the WorkSpace"
  echo "  - Verify the workspace IAM role has AmazonSSMManagedInstanceCore"
  echo "  - Wait 1-2 minutes after AVAILABLE for SSM registration"
  exit 1
fi

echo ""
echo "  Connecting to SSM instance: $INSTANCE_ID"
echo "  Switching to user: humberto.acevedo"
echo "  (Press Ctrl+D or type 'exit' to end the session)"
echo ""
echo "========================================"
echo ""

# Start session and switch to humberto.acevedo user
aws ssm start-session \
  "${AWS_ARGS[@]}" \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo su - humberto.acevedo" \
