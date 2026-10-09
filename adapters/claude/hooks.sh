#!/usr/bin/env bash
# hooks.sh — translate Claude Code hook events into agent operations.

agent_claude_hook_error() { printf 'agent hook claude: %s\n' "$*" >&2; return 1; }

agent_claude_hook() {
  case "$1" in
    SessionStart)
      agent_lifecycle_apply clear
      agent_turns_apply clear
      agent_claude_telemetry_clear
      ;;
    UserPromptSubmit)
      agent_lifecycle_apply working
      agent_turns_apply bump
      ;;
    PermissionRequest)
      agent_lifecycle_apply needs-input
      ;;
    PostToolBatch)
      agent_lifecycle_apply working
      ;;
    Stop)
      agent_lifecycle_apply "done"
      ;;
    SessionEnd)
      agent_lifecycle_apply clear
      agent_turns_apply clear
      agent_claude_telemetry_clear
      ;;
    *)
      agent_claude_hook_error "unknown Claude event: $1"
      ;;
  esac
}
