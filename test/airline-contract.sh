#!/usr/bin/env bash
# Release-only grammar smoke against a selected tmux-airline source checkout.

set -euo pipefail

source_path="${1:-}"
if [[ -z "$source_path" ]]; then
  printf '%s\n' 'airline-contract: set AIRLINE_SOURCE=/path/to/tmux-airline/airline.sh' >&2
  exit 2
fi
if [[ ! -r "$source_path" ]]; then
  printf 'airline-contract: cannot read %s\n' "$source_path" >&2
  exit 2
fi

source_path="$(cd "$(dirname "$source_path")" && pwd)/$(basename "$source_path")"
# shellcheck source=/dev/null
source "$source_path"

# Exercise Airline's real command parser while replacing tmux target resolution
# and mutation below it. The resolver functions are Airline's current mechanical
# tmux boundary; stubbing them keeps this public-grammar smoke test independent
# of a running server and avoids touching Airline state.
resolve_pane() { printf '%s' "$1"; }
resolve_window() { printf '%s' '@9'; }

# Result setting installs Airline's observation hook after parsing. This smoke
# replaces that internal side effect along with storage mutation.
_signal_ensure_result_hook() { :; }

_signal_problem_resolve_pane() {
  local -n destination="$1"
  # shellcheck disable=SC2034 # assignment is through the caller-selected nameref
  destination="$3"
}

declare -a captured=()
_signal_apply() { captured=("$@"); }
# Health has a pane-to-window wrapper before it reaches the common mutation
# pipeline. Capture the same effective tuple as _signal_apply so the assertions
# stay about the public command's parsed arguments.
_signal_health_apply() { captured=(window "$2" health "${@:3}"); }

assert_captured() {
  local -a expected=("$@")
  [[ "${#captured[@]}" -eq "${#expected[@]}" ]] || return 1
  local i
  for ((i = 0; i < ${#expected[@]}; i++)); do
    [[ "${captured[$i]}" == "${expected[$i]}" ]] || return 1
  done
}

contributor=tmux-agent-tools-claude-telemetry
cmd_status set -t %3 active
assert_captured window @9 status _signal_status_set_unlocked @9 %3 3 active

cmd_status set -t %3 result
assert_captured window @9 status _signal_status_set_unlocked @9 %3 3 result

cmd_status clear -t %3
assert_captured window @9 status _signal_status_clear_unlocked @9 %3 3

cmd_health set -t %3 "$contributor" ctx-3 fail 'Claude context window 95% used in pane %3'
assert_captured window @9 health _signal_health_store_unlocked %3 \
  "$contributor" ctx-3 fail 'Claude context window 95% used in pane %3'

cmd_health clear -t %3 "$contributor" ctx-3
assert_captured window @9 health _signal_health_store_unlocked %3 \
  "$contributor" ctx-3 ok ''

cmd_health set -t %3 "$contributor" ctx-3 ok
assert_captured window @9 health _signal_health_store_unlocked %3 \
  "$contributor" ctx-3 ok ''

cmd_problem set -t %3 "$contributor" jq fail 'jq not found'
assert_captured global server problem _signal_problem_claim_set_unlocked \
  pane %3 "$contributor" jq fail 'jq not found'

cmd_problem set -t %3 "$contributor" input ok
assert_captured global server problem _signal_problem_claim_set_unlocked \
  pane %3 "$contributor" input ok ''

cmd_problem resolve "$contributor" jq
assert_captured global server problem _signal_problem_resolve_unlocked \
  "$contributor" jq

cmd_problem close -t %3 "$contributor"
assert_captured global server problem _signal_problem_close_unlocked \
  pane %3 "$contributor" ''

printf 'Airline parser contract accepted Agent status/health/problem vectors\n'
