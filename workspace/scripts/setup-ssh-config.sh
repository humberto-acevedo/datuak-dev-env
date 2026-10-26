#!/bin/bash
# setup-ssh-config.sh
# Update ~/.ssh/config with SSM Session Manager keepalive settings

set -euo pipefail

DRY_RUN=false
SSH_USER="${SSH_USER:-$(whoami)}"

usage() {
  cat << 'USAGE'
setup-ssh-config.sh — Configure ~/.ssh/config for AWS SSM connections

OPTIONS:
  --user <username>   Target user (default: current user)
  --dry-run           Show changes without applying
  --help              Show this help

WHAT IT DOES:
  - Backs up ~/.ssh/config to ~/.ssh/config.bak
  - Adds SSM Session Manager host configuration
  - Sets keepalive intervals to detect stale connections
  - Enables TCPKeepAlive for connection stability

EXAMPLE:
  ./setup-ssh-config.sh
  ./setup-ssh-config.sh --dry-run
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)     SSH_USER="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --help)     usage ;;
    *)          echo "Unknown option: $1"; usage ;;
  esac
done

# Get the home directory for the target user
if [[ "$SSH_USER" == "root" ]]; then
  HOME_DIR="/root"
else
  HOME_DIR=$(eval echo "~$SSH_USER")
fi

SSH_CONFIG="$HOME_DIR/.ssh/config"
SSH_CONFIG_BAK="$HOME_DIR/.ssh/config.bak"

# Create ~/.ssh if it doesn't exist
if [[ ! -d "$HOME_DIR/.ssh" ]]; then
  echo "[*] Creating $HOME_DIR/.ssh directory..."
  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
  fi
fi

# Backup existing config
if [[ -f "$SSH_CONFIG" ]]; then
  echo "[*] Backing up existing config to: $SSH_CONFIG_BAK"
  if [[ "$DRY_RUN" == false ]]; then
    cp "$SSH_CONFIG" "$SSH_CONFIG_BAK"
    echo "    ✓ Backed up"
  fi
fi

# Create temp config snippet
TEMP_SNIPPET=$(mktemp)
cat > "$TEMP_SNIPPET" << 'SNIPPET'

# AWS SSM Session Manager configuration
Host *.ssm
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    ConnectTimeout 30
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# Generic SSM hosts
Host ssm-*
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes

SNIPPET

echo ""
echo "[*] Changes to apply:"
echo "---"
cat "$TEMP_SNIPPET"
echo "---"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  rm "$TEMP_SNIPPET"
  echo "[DRY-RUN] No changes applied. Run without --dry-run to update."
  exit 0
fi

# Append to config if entries don't already exist
if grep -q "AWS SSM Session Manager" "$SSH_CONFIG" 2>/dev/null; then
  echo "[!] SSM configuration already exists in $SSH_CONFIG"
  echo "    Skipping to avoid duplicates."
  rm "$TEMP_SNIPPET"
else
  echo "[*] Adding SSM configuration to $SSH_CONFIG..."
  cat "$TEMP_SNIPPET" >> "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  echo "    ✓ Configuration added"
  rm "$TEMP_SNIPPET"
fi

echo ""
echo "[✓] SSH config updated!"
echo ""
echo "NEXT STEPS:"
echo "  1. Verify changes: cat $SSH_CONFIG"
echo "  2. Test SSM connection"
echo ""
echo "SSH SETTINGS APPLIED:"
echo "  - ServerAliveInterval 60      Keep connection alive every 60 seconds"
echo "  - ServerAliveCountMax 3       Detect stale connection after 3 missed pings"
echo "  - TCPKeepAlive yes            Enable TCP keepalive at OS level"
echo "  - ConnectTimeout 30           Fail if connection takes >30 seconds"
