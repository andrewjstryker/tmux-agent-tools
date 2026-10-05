#!/usr/bin/env bash
# airline.sh — discover and validate tmux-airline's public CLI.
# Callers invoke the resolved executable using Airline's public grammar.

AGENT_AIRLINE_VERSION_RANGE='>= 3.0.0 and < 4.0.0'

agent_airline_discover() {
  if [[ -n "${AIRLINE_BIN:-}" ]]; then
    printf '%s' "$AIRLINE_BIN"
    return 0
  fi
  agent_tmux_global_get @airline-cli 2>/dev/null
}

agent_airline_warn_once() { # <category> <prefix> <message>
  local category="$1" prefix="$2" message="$3"
  local flag="@agent-tools-$category-warned"
  [[ "$(agent_tmux_global_get "$flag" 2>/dev/null)" == 1 ]] && return 0
  agent_tmux_global_set "$flag" 1 2>/dev/null
  printf '%s: %s\n' "$prefix" "$message" >&2
}

agent_airline_warn_missing() { # <diagnostic-prefix>
  agent_airline_warn_once airline "$1" \
    'airline CLI not found — set @airline-cli (load tmux-airline first) or the AIRLINE_BIN env var; Airline-backed signals disabled'
}

# Print the major component of a strict, stable SemVer response. Airline's
# release/API version command reports a release version rather than a range or
# decorated product string, so prerelease/build forms are not part of this
# bootstrap contract.
agent_airline_version_major() { # <version>
  local version="$1"
  if [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

agent_airline_executable() { # <resolved-cli>
  if [[ "$1" == */* ]]; then
    [[ -x "$1" ]]
  else
    command -v "$1" >/dev/null 2>&1
  fi
}

# Resolve a compatible Airline CLI, warning once per tmux server and returning
# an empty result for every degraded installation. Callers treat empty as a
# successful no-op so hooks and Claude's statusLine pipeline keep working.
agent_airline_resolve() { # [diagnostic-prefix]
  local prefix="${1:-agent}" cli version major
  cli=$(agent_airline_discover)
  if [[ -z "$cli" ]]; then
    agent_airline_warn_missing "$prefix"
    return 0
  fi
  if ! agent_airline_executable "$cli"; then
    agent_airline_warn_once airline "$prefix" \
      "airline CLI is not executable: $cli; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  if ! version=$("$cli" version 2>/dev/null); then
    agent_airline_warn_once airline "$prefix" \
      "airline version command failed; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  if ! major=$(agent_airline_version_major "$version"); then
    agent_airline_warn_once airline "$prefix" \
      "malformed airline version response: $version; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  if [[ "$major" != 3 ]]; then
    agent_airline_warn_once airline "$prefix" \
      "incompatible airline version $version; requires $AGENT_AIRLINE_VERSION_RANGE; Airline-backed signals disabled"
    return 0
  fi
  printf '%s' "$cli"
}

# vim: ft=bash
