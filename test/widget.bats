#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "standalone widget emits a native format without tmux or Airline" {
  run env -u TMUX -u TMUX_PANE bash "$ROOT/widgets/agent-turns.sh"
  [[ "$status" -eq 0 ]]
  [[ "$output" == '#{?@agent-tools-turns,#{@agent-tools-turns}⟳,}' ]]
}

@test "Airline can source the widget quietly and supply placement colors" {
  run bash -c 'source "$1"' _ "$ROOT/widgets/agent-turns.sh"
  [[ "$status" -eq 0 && -z "$output" ]]
  source "$ROOT/widgets/agent-turns.sh"
  run airline_widget_format white black
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$(bash "$ROOT/widgets/agent-turns.sh")" ]]
}
