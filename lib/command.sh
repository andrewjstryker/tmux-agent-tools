#!/usr/bin/env bash
# Shared utilities for the public Agent command boundary.

# Return instead of exiting so a sourced agent.sh remains testable. When
# agent.sh is executed, its final status is still the CLI process status.
agent_command_die() {
  printf 'agent: %s\n' "$*" >&2
  return 2
}

agent_command_version() {
  [ "$#" -eq 0 ] || {
    agent_command_die "version: takes no arguments"
    return
  }

  local version
  IFS= read -r version < "$AGENT_DIR/VERSION" || {
    agent_command_die "version: cannot read VERSION"
    return
  }
  printf '%s\n' "$version"
}
