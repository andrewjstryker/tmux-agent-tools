#!/usr/bin/env bash
# Initialization records an attempt per session, including standalone operation.
agent_initialize() { # [reset]
  local session cli
  local -a target=()
  [[ -z "${TMUX_PANE:-}" ]] || target=(-t "$TMUX_PANE")
  session=$(tmux display-message -p "${target[@]}" '#{session_id}' 2>/dev/null) || return 1
  [[ -n "$session" ]] || return 1

  if [[ "${1:-}" == reset || "$(tmux show -qv -t "$session" @agent-tools-init)" != 1 ]]; then
    # Concurrent first hooks share one initialization attempt. The hot path does
    # not acquire the lock. Scope the trap to this short-lived subshell.
    (
      local lock="agent-tools-init-$session"
      tmux wait-for -L "$lock" || exit
      trap 'tmux wait-for -U "$lock"' EXIT
      if [[ "${1:-}" == reset ]]; then
        tmux set -u -t "$session" @agent-tools-init || exit
      elif [[ "$(tmux show -qv -t "$session" @agent-tools-init)" == 1 ]]; then
        exit 0
      fi
      # Never discover Airline through PATH or a guessed executable location.
      cli=$(tmux show -gqv @airline-cli 2>/dev/null)
      AGENT_AIRLINE_CLI=''
      if [[ -n "$cli" ]]; then
        AGENT_AIRLINE_CLI=$(agent_airline_validate "$cli")
        if [[ -n "$AGENT_AIRLINE_CLI" ]]; then
          if ! "$AGENT_AIRLINE_CLI" widget register "$AGENT_DIR/widgets"; then
            agent_warn_once init 'agent init' 'Airline widget registration failed; run agent init to retry'
          fi
        fi
      fi
      tmux set -t "$session" @agent-tools-airline-cli "$AGENT_AIRLINE_CLI" || exit
      # Completion means available setup was attempted, not that Airline exists.
      tmux set -t "$session" @agent-tools-init 1
    ) || return
  fi
  AGENT_AIRLINE_CLI=$(tmux show -qv -t "$session" @agent-tools-airline-cli)
}

agent_command_init() {
  [[ "$#" -eq 0 ]] || { agent_command_die 'init: takes no arguments'; return; }
  agent_initialize reset || agent_command_die 'init: cannot initialize the current tmux session'
}
