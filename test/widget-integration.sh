#!/usr/bin/env bash
# Real tmux rendering and optional Airline registration on an isolated server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTDIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-widget.XXXXXX")
cleanup() {
  tmux -S "$TESTDIR/socket" kill-server 2>/dev/null || true
  rm -rf "$TESTDIR"
}
trap cleanup EXIT
unset TMUX TMUX_PANE airline_cli
tmux -S "$TESTDIR/socket" -f /dev/null new-session -d -s agent 'sleep 120'
export TMUX="$TESTDIR/socket,0,0"
TMUX_PANE=$(tmux display-message -p -t agent:0.0 '#{pane_id}')
export TMUX_PANE
format=$(bash "$ROOT/widgets/agent-turns.sh")
[[ -z "$(tmux display-message -p -t "$TMUX_PANE" "$format")" ]]
"$ROOT/agent.sh" turns bump
"$ROOT/agent.sh" turns bump
[[ "$(tmux display-message -p -t "$TMUX_PANE" "$format")" == '2⟳' ]]
other=$(tmux split-window -d -P -F '#{pane_id}' -t "$TMUX_PANE" 'sleep 120')
[[ -z "$(tmux display-message -p -t "$other" "$format")" ]]
"$ROOT/agent.sh" turns clear
[[ -z "$(tmux display-message -p -t "$TMUX_PANE" "$format")" ]]

if [[ -n "${1:-}" ]]; then
  airline_cli="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  "$airline_cli" session init
  [[ "$(tmux show -qv @agent-tools-init)" == 1 ]]
  [[ -z "$(tmux show -qv @agent-tools-airline-cli)" ]]
  bash "$ROOT/agent.tmux"
  [[ "$(tmux show -qv @agent-tools-airline-cli)" == "$airline_cli" ]]
  "$airline_cli" widget describe agent-turns > "$TESTDIR/description"
  grep -Fq "$format" "$TESTDIR/description"
  cat > "$TESTDIR/turns-layout.sh" <<'LAYOUT'
airline_layout_configure() {
  "$1" segment right-in '#{E:@airline--widget-agent-turns}'
}
LAYOUT
  "$airline_cli" layout load "$TESTDIR/turns-layout.sh"
  "$ROOT/agent.sh" hook codex UserPromptSubmit
  [[ "$(tmux display-message -p -t "$TMUX_PANE" '#{E:@airline--widget-agent-turns}')" == *'1⟳'* ]]
  "$airline_cli" status show | grep -q active
  "$ROOT/agent.sh" hook codex SessionEnd
  [[ -z "$(tmux display-message -p -t "$TMUX_PANE" "$format")" ]]
  tmux new-session -d -s second 'sleep 120'
  second=$(tmux display-message -p -t second:0.0 '#{pane_id}')
  [[ -z "$(tmux show -qv -t second @agent-tools-init)" ]]
  TMUX_PANE="$second" "$ROOT/agent.sh" turns bump
  [[ "$(tmux show -qv -t second @agent-tools-init)" == 1 ]]
  TMUX_PANE="$second" "$airline_cli" widget describe agent-turns > "$TESTDIR/second-description"
  grep -Fq "$format" "$TESTDIR/second-description"
fi
printf '%s\n' 'Turn widget rendering, pane isolation, and configured integration passed'
