#!/usr/bin/env bash
#| summary: Conversation turns in the active pane
# Native tmux format: no Airline state, styles, or runtime polling required.
airline_widget_format() {
  printf '%s' '#{?@agent-tools-turns,#{@agent-tools-turns}⟳,}'
}

# Also usable as a standalone format provider for a plain tmux status line.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  airline_widget_format
fi
