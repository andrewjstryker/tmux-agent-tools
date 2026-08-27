#!/usr/bin/env bash
# hooks.sh — translate Claude Code hook events into agent operations.

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$ADAPTER_DIR/../.." && pwd)"

CH_STATE_BIN="${AGENT_STATE_BIN:-$PROJECT_DIR/lib/lifecycle.sh}"
CH_TURNS_BIN="${AGENT_TURNS_BIN:-$PROJECT_DIR/lib/turns.sh}"
CH_CONTEXT_BIN="${CLAUDE_CONTEXT_BIN:-$ADAPTER_DIR/context.sh}"

ch_die() { printf 'claude-hooks: %s\n' "$*" >&2; return 1; }

ch_apply() {
  case "$1" in
    SessionStart)
      "$CH_STATE_BIN" clear
      "$CH_TURNS_BIN" reset
      "$CH_CONTEXT_BIN" clear
      ;;
    UserPromptSubmit)
      "$CH_STATE_BIN" working
      "$CH_TURNS_BIN" bump
      ;;
    PostToolUse)
      "$CH_STATE_BIN" working
      ;;
    Notification)
      "$CH_STATE_BIN" needs-input
      ;;
    Stop)
      "$CH_STATE_BIN" "done"
      ;;
    SessionEnd)
      "$CH_STATE_BIN" clear
      "$CH_TURNS_BIN" reset
      "$CH_CONTEXT_BIN" clear
      ;;
    *)
      ch_die "unknown Claude event: $1"
      ;;
  esac
}

ch_main() {
  set -euo pipefail
  [ $# -eq 1 ] || ch_die "usage: hooks.sh <SessionStart|UserPromptSubmit|PostToolUse|Notification|Stop|SessionEnd>"
  ch_apply "$1"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  ch_main "$@"
fi
