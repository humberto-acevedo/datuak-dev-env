#!/bin/bash
# tmux-workflow.sh - Manage tmux sessions for AWS WorkSpace connections
# Usage: ./tmux-workflow.sh [list|new|attach|detach|kill|help]

set -euo pipefail

check_tmux() {
  if ! command -v tmux &> /dev/null; then
    echo "ERROR: tmux not installed. Run: sudo apt-get install tmux"
    exit 1
  fi
}

list_sessions() {
  echo "Active tmux sessions:"
  tmux list-sessions -F "  #{session_name}: #{session_windows} window(s)" 2>/dev/null || echo "  (none)"
}

create_session() {
  local name="${1:-work}"
  if tmux has-session -t "$name" 2>/dev/null; then
    echo "✓ Session '$name' already exists"
  else
    tmux new-session -d -s "$name"
    echo "✓ Created session '$name'"
  fi
}

attach_session() {
  local count=$(tmux list-sessions 2>/dev/null | wc -l || echo 0)
  if [[ $count -eq 0 ]]; then
    echo "No sessions found. Create: tmux new-session -s work"
    exit 1
  elif [[ $count -eq 1 ]]; then
    local session=$(tmux list-sessions -F "#{session_name}" | head -1)
    tmux attach-session -t "$session"
  else
    tmux list-sessions
    read -p "Enter session name: " session
    tmux attach-session -t "$session"
  fi
}

kill_session() {
  local name="$1"
  if tmux has-session -t "$name" 2>/dev/null; then
    tmux kill-session -t "$name"
    echo "✓ Killed session '$name'"
  else
    echo "Session not found: $name"
    exit 1
  fi
}

show_help() {
  cat << 'HELP'
tmux-workflow.sh — Manage AWS WorkSpace tmux sessions

ACTIONS:
  list              List all sessions
  new [name]        Create new session (default: work)
  attach            Attach to existing session
  detach            Show detach instructions
  kill <name>       Kill a session
  help              Show this help

WORKFLOW (sessions survive SSH disconnect):
  1. Connect: ./start-and-connect.sh
  2. Create: tmux new-session -d -s work
  3. Work...
  4. Detach: Ctrl+B then D (or: tmux detach)
  5. SSH disconnects (normal)
  6. Reconnect: ./start-and-connect.sh
  7. Reattach: ./tmux-workflow.sh attach
HELP
}

check_tmux
case "${1:-help}" in
  list)   list_sessions ;;
  new)    create_session "${2:-work}" ;;
  attach) attach_session ;;
  detach) echo "Detach: Press Ctrl+B then D (or: tmux detach)" ;;
  kill)   kill_session "$2" ;;
  help)   show_help ;;
  *)      echo "Unknown action: $1"; show_help; exit 1 ;;
esac
