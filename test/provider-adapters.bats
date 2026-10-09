#!/usr/bin/env bats
# Provider adapters translate native event names into the shared operations.

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TESTDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/agadapters.XXXXXX")"
  export FAKE_TMUX_STATE_DIR="$TESTDIR/tmux-state"
  export ADAPTER_LOG="${TESTDIR}/adapter.log"
  : > "$ADAPTER_LOG"

  source "$ROOT/agent.sh"
  agent_lifecycle_apply() { printf 'state %s\n' "$*" >> "$ADAPTER_LOG"; }
  agent_turns_apply() { printf 'turns %s\n' "$*" >> "$ADAPTER_LOG"; }
  agent_claude_telemetry_clear() { printf 'telemetry clear\n' >> "$ADAPTER_LOG"; }

}

teardown() {
  [ -n "${TESTDIR:-}" ] && rm -rf "$TESTDIR"
}

@test "Claude prompt starts work and increments the turn" {
  agent_claude_hook UserPromptSubmit
  grep -qx "state working" "$ADAPTER_LOG"
  grep -qx "turns bump" "$ADAPTER_LOG"
}

@test "Claude permission request requests attention" {
  agent_claude_hook PermissionRequest
  [ "$(cat "$ADAPTER_LOG")" = "state needs-input" ]
}

@test "Claude post-tool batch returns to working" {
  agent_claude_hook PostToolBatch
  [ "$(cat "$ADAPTER_LOG")" = "state working" ]
}

@test "Claude stop records a completed result" {
  agent_claude_hook Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done" ]
}

@test "Claude configured session boundaries clear every Claude-owned operation" {
  local event
  for event in SessionStart SessionEnd; do
    : > "$ADAPTER_LOG"
    agent_claude_hook "$event"
    grep -qx "state clear" "$ADAPTER_LOG"
    grep -qx "turns clear" "$ADAPTER_LOG"
    grep -qx "telemetry clear" "$ADAPTER_LOG"
  done
}

@test "Codex prompt starts work and increments the turn" {
  agent_codex_hook UserPromptSubmit
  grep -qx "state working" "$ADAPTER_LOG"
  grep -qx "turns bump" "$ADAPTER_LOG"
}

@test "Codex permission request requests attention" {
  agent_codex_hook PermissionRequest
  [ "$(cat "$ADAPTER_LOG")" = "state needs-input" ]
}

@test "Codex post-tool event returns to working" {
  agent_codex_hook PostToolUse
  [ "$(cat "$ADAPTER_LOG")" = "state working" ]
}

@test "Codex stop records a completed result" {
  agent_codex_hook Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done" ]
}

@test "Codex configured session boundaries clear shared state without Claude telemetry" {
  local event
  for event in SessionStart SessionEnd; do
    : > "$ADAPTER_LOG"
    agent_codex_hook "$event"
    grep -qx "state clear" "$ADAPTER_LOG"
    grep -qx "turns clear" "$ADAPTER_LOG"
    ! grep -q "telemetry" "$ADAPTER_LOG"
  done
}

@test "provider adapters reject events from the other provider" {
  run agent_codex_hook Notification
  [ "$status" -ne 0 ]
  run agent_codex_hook PostToolBatch
  [ "$status" -ne 0 ]
  run agent_claude_hook PostToolUse
  [ "$status" -ne 0 ]
  run agent_claude_hook Notification
  [ "$status" -ne 0 ]
}

@test "checked-in provider configurations are valid JSON and use the public CLI" {
  jq -e . "$ROOT/examples/claude-settings.json" "$ROOT/examples/codex-hooks.json" >/dev/null
  jq -r '.. | objects | .command? // empty' "$ROOT/examples/claude-settings.json" |
    grep -q '"$cli" hook claude'
  jq -r '.. | objects | .command? // empty' "$ROOT/examples/codex-hooks.json" |
    grep -q '"$cli" hook codex'
  grep -q '@agent-cli' "$ROOT/examples/claude-settings.json" "$ROOT/examples/codex-hooks.json"
  ! grep -qE '@agent-tools-(state|turns|claude|codex|claude-context)-bin' \
    "$ROOT/examples/claude-settings.json" "$ROOT/examples/codex-hooks.json"
}

@test "provider configurations reset only for startup or clear" {
  local config matcher
  for config in claude-settings.json codex-hooks.json; do
    run jq -er '.hooks.SessionStart | length == 1 and .[0].matcher == "startup|clear"' \
      "$ROOT/examples/$config"
    [ "$status" -eq 0 ]
    [ "$output" = true ]
    matcher="$(jq -r '.hooks.SessionStart[0].matcher' "$ROOT/examples/$config")"
    [[ startup =~ ^($matcher)$ ]]
    [[ clear =~ ^($matcher)$ ]]
    [[ ! resume =~ ^($matcher)$ ]]
    [[ ! compact =~ ^($matcher)$ ]]
  done
}

@test "Claude configuration uses only the coarse native lifecycle events" {
  run jq -er \
    '.hooks | keys | sort == ["PermissionRequest", "PostToolBatch", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"]' \
    "$ROOT/examples/claude-settings.json"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "Codex configuration retains its supported native lifecycle events" {
  run jq -er \
    '.hooks | keys | sort == ["PermissionRequest", "PostToolUse", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"]' \
    "$ROOT/examples/codex-hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "each configured event is passed unchanged through the public CLI" {
  local provider config event command
  while IFS=$'\t' read -r provider config; do
    while IFS=$'\t' read -r event command; do
      [[ "$command" == *'"$cli" hook '"$provider $event"'; fi' ]]
    done < <(jq -r \
      '.hooks | to_entries[] | .key as $event | .value[].hooks[].command | [$event, .] | @tsv' \
      "$ROOT/examples/$config")
  done <<'CONFIGS'
claude	claude-settings.json
codex	codex-hooks.json
CONFIGS
}

@test "provider dispatch calls operations in the current shell" {
  local lifecycle_seen='' turns_seen=''
  agent_lifecycle_apply() { lifecycle_seen="$1"; }
  agent_turns_apply() { turns_seen="$1"; }
  agent_main hook codex UserPromptSubmit
  [[ "$lifecycle_seen" == working && "$turns_seen" == bump ]]
  lifecycle_seen='' turns_seen=''
  agent_main hook claude UserPromptSubmit
  [[ "$lifecycle_seen" == working && "$turns_seen" == bump ]]
}
