#!/usr/bin/env bash
# hooks.sh — translate Codex hook events into agent operations.

agent_codex_hook_error() { printf 'agent hook codex: %s\n' "$*" >&2; return 1; }

agent_codex_hook() {
  case "$1" in
    SessionStart)
      agent_lifecycle_apply clear
      agent_turns_apply clear
      ;;
    UserPromptSubmit)
      agent_lifecycle_apply working
      agent_turns_apply bump
      ;;
    PermissionRequest)
      agent_lifecycle_apply needs-input
      ;;
    PostToolUse)
      agent_lifecycle_apply working
      ;;
    Stop)
      agent_lifecycle_apply "done"
      ;;
    Interrupt)
      # The user interrupted from this pane, so there is no result to announce.
      agent_lifecycle_apply clear
      ;;
    SessionEnd)
      agent_lifecycle_apply clear
      agent_turns_apply clear
      ;;
    *)
      agent_codex_hook_error "unknown Codex event: $1"
      ;;
  esac
}
