#!/usr/bin/env bash
# tmux-agent-tools — TPM entry point.
#
# A small toolkit with two explicit layers: provider-neutral operations under
# operations/, and agent-specific adapters under adapters/. Operations own the
# tmux-airline/plain-tmux contracts; adapters translate Claude and Codex events.
#
#   * lifecycle.sh     <state>  lifecycle      -> a status badge (a glyph before
#                                                 the window name) at airline's
#                                                 active/result/attention level.
#                                                 Event signal.
#   * adapters/claude/context.sh
#                              context+usage  -> a condition glyph in the window's
#                                                right health gutter (airline
#                                                health), adapted from Claude
#                                                Code's statusLine JSON.
#   * turns.sh         <cmd>    turn counter   -> a per-pane count in the
#                                                 @agent-tools-turns pane option,
#                                                 you render wherever your status
#                                                 line evaluates formats.
#
# The three signals are independent and coexist: a working window (○ active badge)
# can also be near its context limit (red gutter glyph) and show a turn count.
# The core operations know nothing about a specific agent. Provider adapters
# translate their own event and payload formats into those operations / airline.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/tmux.sh
source "$CURRENT_DIR/lib/tmux.sh"

# Publish both layers so agent configuration never hardcodes the install dir:
#   "$(tmux show -gqv @agent-tools-state-bin)"          needs-input
#   "$(tmux show -gqv @agent-tools-claude-bin)"         Notification
#   "$(tmux show -gqv @agent-tools-codex-bin)"          PermissionRequest
#   "$(tmux show -gqv @agent-tools-claude-context-bin)" # Claude statusLine adapter
#   "$(tmux show -gqv @agent-tools-turns-bin)"          bump
agent_tmux_global_set @agent-tools-state-bin          "$CURRENT_DIR/operations/lifecycle.sh"
agent_tmux_global_set @agent-tools-claude-context-bin "$CURRENT_DIR/adapters/claude/context.sh"
agent_tmux_global_set @agent-tools-claude-bin         "$CURRENT_DIR/adapters/claude/hooks.sh"
agent_tmux_global_set @agent-tools-codex-bin          "$CURRENT_DIR/adapters/codex/hooks.sh"
agent_tmux_global_set @agent-tools-turns-bin          "$CURRENT_DIR/operations/turns.sh"

# No registration step. airline's status keys are created implicitly on the first
# `status set`, and its glyphs are fixed per level (○ active, ● result, ◆
# attention) rather than picked by the caller — so the plugin has nothing to
# register at load. The operations resolve the airline CLI themselves (via
# @airline-cli / $AIRLINE_BIN) at call time and no-op when it's absent, so this
# loader only needs to publish the operation and adapter paths above.
