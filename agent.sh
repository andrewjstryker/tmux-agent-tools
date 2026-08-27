#!/usr/bin/env bash
# agent.sh — public CLI grammar and single-dispatch boundary.

set -u

AGENT_DIR="${AGENT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# shellcheck source=lib/command.sh
source "$AGENT_DIR/lib/command.sh"
# shellcheck source=lib/lifecycle.sh
source "$AGENT_DIR/lib/lifecycle.sh"
# shellcheck source=lib/turns.sh
source "$AGENT_DIR/lib/turns.sh"
# shellcheck source=adapters/claude/context.sh
source "$AGENT_DIR/adapters/claude/context.sh"
# shellcheck source=adapters/claude/hooks.sh
source "$AGENT_DIR/adapters/claude/hooks.sh"
# shellcheck source=adapters/codex/hooks.sh
source "$AGENT_DIR/adapters/codex/hooks.sh"

AGENT_NOUNS="lifecycle turns hook telemetry"
AGENT_HELP_SOURCE="$AGENT_DIR/agent.sh"
# shellcheck source=lib/help.sh
source "$AGENT_DIR/lib/help.sh"

agent_usage_error() {
  agent_command_die "$1 (try: agent help ${2:-})"
}

cmd_lifecycle() {
  local verb="${1:-}"
  shift || true
  # help:begin lifecycle
  case "$verb" in
    set) #| <working|needs-input|done> — set the calling pane's lifecycle state
      [[ "$#" -eq 1 ]] || {
        agent_usage_error "lifecycle set: expected one state" "lifecycle set"
        return
      }
      case "$1" in
        working|needs-input|done) as_apply "$1" ;;
        *) agent_usage_error "lifecycle set: unknown state '$1'" "lifecycle set" ;;
      esac
      ;;
    clear) #| — clear the calling pane's lifecycle state
      [[ "$#" -eq 0 ]] || {
        agent_usage_error "lifecycle clear: takes no arguments" "lifecycle clear"
        return
      }
      as_apply clear
      ;;
    *) agent_usage_error "unknown lifecycle command: $verb" lifecycle ;;
  esac
  # help:end lifecycle
}

cmd_turns() {
  local verb="${1:-}"
  shift || true
  # help:begin turns
  case "$verb" in
    bump) #| — increment the calling pane's conversation-turn count
      [[ "$#" -eq 0 ]] || {
        agent_usage_error "turns bump: takes no arguments" "turns bump"
        return
      }
      at_apply bump
      ;;
    clear) #| — clear the calling pane's conversation-turn count
      [[ "$#" -eq 0 ]] || {
        agent_usage_error "turns clear: takes no arguments" "turns clear"
        return
      }
      at_apply clear
      ;;
    *) agent_usage_error "unknown turns command: $verb" turns ;;
  esac
  # help:end turns
}

cmd_hook() {
  local provider="${1:-}"
  shift || true
  # help:begin hook
  case "$provider" in
    claude) #| <event> — handle one exact, case-sensitive Claude event
      [[ "$#" -eq 1 ]] || {
        agent_usage_error "hook claude: expected one event" "hook claude"
        return
      }
      ch_apply "$1"
      ;;
    codex) #| <event> — handle one exact, case-sensitive Codex event
      [[ "$#" -eq 1 ]] || {
        agent_usage_error "hook codex: expected one event" "hook codex"
        return
      }
      cx_apply "$1"
      ;;
    *) agent_usage_error "unknown hook provider: $provider" hook ;;
  esac
  # help:end hook
}

cmd_telemetry() {
  local provider="${1:-}"
  shift || true
  # help:begin telemetry
  case "$provider" in
    claude) #| <update|clear> — update or clear Claude context and usage telemetry
      [[ "$#" -eq 1 ]] || {
        agent_usage_error "telemetry claude: expected update or clear" "telemetry claude"
        return
      }
      case "$1" in
        update) ac_apply ;;
        clear) ac_clear ;;
        *) agent_usage_error "telemetry claude: unknown command '$1'" "telemetry claude" ;;
      esac
      ;;
    *) agent_usage_error "unknown telemetry provider: $provider" telemetry ;;
  esac
  # help:end telemetry
}

agent_main() {
  local command="${1:-}"
  shift || true
  # help:begin root
  case "$command" in
    lifecycle) cmd_lifecycle "$@" ;;
    turns) cmd_turns "$@" ;;
    hook) cmd_hook "$@" ;;
    telemetry) cmd_telemetry "$@" ;;
    version) agent_command_version "$@" ;; #| — show the Agent release/API version
    help) agent_help_command "$@" ;; #| [<noun> [<verb>]] — show command help
    ""|-h|--help) agent_help_command ;;
    *) agent_usage_error "unknown command: $command" ;;
  esac
  # help:end root
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  agent_main "$@"
  exit $?
fi
