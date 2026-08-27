#!/usr/bin/env bash
# hooks.sh — translate Codex hook events into agent operations.

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$ADAPTER_DIR/../.." && pwd)"

CX_STATE_BIN="${AGENT_STATE_BIN:-$PROJECT_DIR/operations/lifecycle.sh}"
CX_TURNS_BIN="${AGENT_TURNS_BIN:-$PROJECT_DIR/operations/turns.sh}"

cx_die() { printf 'codex-hooks: %s\n' "$*" >&2; return 1; }

cx_apply() {
  case "$1" in
    SessionStart)
      "$CX_STATE_BIN" clear
      "$CX_TURNS_BIN" reset
      ;;
    UserPromptSubmit)
      "$CX_STATE_BIN" working
      "$CX_TURNS_BIN" bump
      ;;
    PermissionRequest)
      "$CX_STATE_BIN" needs-input
      ;;
    PostToolUse)
      "$CX_STATE_BIN" working
      ;;
    Stop)
      "$CX_STATE_BIN" "done"
      ;;
    SessionEnd)
      "$CX_STATE_BIN" clear
      "$CX_TURNS_BIN" reset
      ;;
    *)
      cx_die "unknown Codex event: $1"
      ;;
  esac
}

cx_main() {
  set -euo pipefail
  [ $# -eq 1 ] || cx_die "usage: hooks.sh <SessionStart|UserPromptSubmit|PermissionRequest|PostToolUse|Stop|SessionEnd>"
  cx_apply "$1"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cx_main "$@"
fi
