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
  agent_codex_pane_resolve() { printf '%%7'; }
  agent_codex_pane_release() { :; }
  CLAUDE_HOOKS="$ROOT/plugins/claude/hooks/hooks.json"
  CODEX_HOOKS="$ROOT/plugins/codex/hooks/hooks.json"

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

@test "Claude API failure ends the turn like stop" {
  agent_claude_hook StopFailure
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

@test "Codex interrupt clears status but keeps the turn count" {
  agent_codex_hook Interrupt
  [ "$(cat "$ADAPTER_LOG")" = "state clear" ]
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

@test "Codex operations target the resolved session pane" {
  agent_lifecycle_apply() { printf 'state %s %s\n' "$1" "$TMUX_PANE" >> "$ADAPTER_LOG"; }
  TMUX_PANE=%9 agent_codex_hook Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done %7" ]
}

@test "Codex operations get no pane when the session pane is unknown" {
  agent_codex_pane_resolve() { return 1; }
  agent_lifecycle_apply() { printf 'state %s [%s]\n' "$1" "$TMUX_PANE" >> "$ADAPTER_LOG"; }
  TMUX_PANE=%9 agent_codex_hook Stop
  [ "$(cat "$ADAPTER_LOG")" = "state done []" ]
}

@test "provider adapters reject events from the other provider" {
  run agent_codex_hook Notification
  [ "$status" -ne 0 ]
  run agent_codex_hook PostToolBatch
  [ "$status" -ne 0 ]
  run agent_codex_hook StopFailure
  [ "$status" -ne 0 ]
  run agent_claude_hook PostToolUse
  [ "$status" -ne 0 ]
  run agent_claude_hook Interrupt
  [ "$status" -ne 0 ]
  run agent_claude_hook Notification
  [ "$status" -ne 0 ]
}

@test "checked-in plugin hooks are valid JSON and use the public CLI" {
  jq -e . "$CLAUDE_HOOKS" "$CODEX_HOOKS" >/dev/null
  jq -r '.. | objects | .command? // empty' "$CLAUDE_HOOKS" | grep -q '"$cli" hook claude'
  jq -r '.. | objects | .command? // empty' "$CODEX_HOOKS" | grep -q '"$cli" hook codex'
  grep -q '@agent-cli' "$CLAUDE_HOOKS" "$CODEX_HOOKS"
  ! grep -qE '@agent-tools-(state|turns|claude|codex|claude-context)-bin' \
    "$CLAUDE_HOOKS" "$CODEX_HOOKS"
}

@test "plugin hooks reset at startup or clear but not on resume, compaction, or fork" {
  local config matcher
  for config in "$CLAUDE_HOOKS" "$CODEX_HOOKS"; do
    run jq -er '.hooks.SessionStart | length == 1 and .[0].matcher == "startup|clear"' "$config"
    [ "$status" -eq 0 ]
    [ "$output" = true ]
    matcher="$(jq -r '.hooks.SessionStart[0].matcher' "$config")"
    [[ startup =~ ^($matcher)$ ]]
    [[ clear =~ ^($matcher)$ ]]
    [[ ! resume =~ ^($matcher)$ ]]
    [[ ! compact =~ ^($matcher)$ ]]
    [[ ! fork =~ ^($matcher)$ ]]
  done
}

@test "Claude session end leaves resume and clear to the next session start" {
  local matcher
  matcher="$(jq -er '.hooks.SessionEnd[0].matcher' "$CLAUDE_HOOKS")"
  [[ prompt_input_exit =~ ^($matcher)$ ]]
  [[ logout =~ ^($matcher)$ ]]
  [[ other =~ ^($matcher)$ ]]
  [[ ! resume =~ ^($matcher)$ ]]
  [[ ! clear =~ ^($matcher)$ ]]
}

@test "Claude plugin uses only the coarse native lifecycle events" {
  run jq -er \
    '.hooks | keys | sort == ["PermissionRequest", "PostToolBatch", "SessionEnd", "SessionStart", "Stop", "StopFailure", "UserPromptSubmit"]' \
    "$CLAUDE_HOOKS"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "Codex plugin retains its supported native lifecycle events" {
  run jq -er \
    '.hooks | keys | sort == ["Interrupt", "PermissionRequest", "PostToolUse", "SessionEnd", "SessionStart", "Stop", "UserPromptSubmit"]' \
    "$CODEX_HOOKS"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "Codex shutdown hooks raise the one-second default timeout" {
  run jq -er '[.hooks.SessionEnd, .hooks.Interrupt | .[].hooks[].timeout] == [3, 3]' "$CODEX_HOOKS"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "each configured event is passed unchanged through the public CLI" {
  local provider config event command
  while IFS=$'\t' read -r provider config; do
    while IFS=$'\t' read -r event command; do
      [[ "$command" == 'if [ -n "$TMUX" ] && '* ]]
      [[ "$command" == *'"$cli" hook '"$provider $event"'; fi' ]]
    done < <(jq -r \
      '.hooks | to_entries[] | .key as $event | .value[].hooks[].command | [$event, .] | @tsv' \
      "$config")
  done <<CONFIGS
claude	$CLAUDE_HOOKS
codex	$CODEX_HOOKS
CONFIGS
}

@test "every plugin event is accepted by its provider adapter" {
  local event
  for event in $(jq -r '.hooks | keys[]' "$CLAUDE_HOOKS"); do
    agent_claude_hook "$event"
  done
  for event in $(jq -r '.hooks | keys[]' "$CODEX_HOOKS"); do
    agent_codex_hook "$event"
  done
}

@test "Claude marketplace publishes the Claude plugin directory" {
  run jq -er '.plugins == [.plugins[] | select(.source == "./plugins/claude")] and (.plugins | length == 1)' \
    "$ROOT/.claude-plugin/marketplace.json"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
  [ "$(jq -r .name "$ROOT/plugins/claude/.claude-plugin/plugin.json")" = \
    "$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")" ]
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

# Codex falls back to .claude-plugin/marketplace.json, which would install the
# Claude hooks, unless its own marketplace file exists.
@test "Codex marketplace publishes the Codex plugin directory" {
  run jq -er '[.plugins[].source.path] == ["./plugins/codex"]' \
    "$ROOT/.agents/plugins/marketplace.json"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
  [ "$(jq -r .name "$ROOT/plugins/codex/.codex-plugin/plugin.json")" = \
    "$(jq -r '.plugins[0].name' "$ROOT/.agents/plugins/marketplace.json")" ]
  # A manifest hooks field would disable discovery of hooks/hooks.json.
  run jq -e 'has("hooks")' "$ROOT/plugins/codex/.codex-plugin/plugin.json"
  [ "$status" -ne 0 ]
}
