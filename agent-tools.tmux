#!/usr/bin/env bash
# tmux-agent-tools — TPM entry point.
#
# A small toolkit that surfaces agent signal in the tmux-airline window list and
# status line. Three independent, agent-agnostic setters, each driven through a
# supported API (airline's CLI, or a plain tmux option) so no private option
# names are touched:
#
#   * agent-state.sh   <state>  lifecycle      -> a status badge (a glyph before
#                                                 the window name) at airline's
#                                                 active/result/attention level.
#                                                 Event signal.
#   * integrations/claude-context.sh
#                              context+usage  -> a severity glyph in the window's
#                                                right health gutter (airline
#                                                health), adapted from Claude
#                                                Code's statusLine JSON.
#   * agent-turns.sh   <cmd>    turn counter   -> a per-pane count in the
#                                                 @agent-tools-turns pane option,
#                                                 you render wherever your status
#                                                 line evaluates formats.
#
# The three are independent and coexist: a working window (○ active badge) can
# also be near its context limit (red gutter glyph) and show a turn count. None
# The core setters know nothing about a specific agent. Provider integrations
# translate their own event and payload formats into those setters / airline.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Publish each setter's path so agent hooks / statusLine need not hardcode the
# install dir:
#   "$(tmux show -gqv @agent-tools-state-bin)"          needs-input
#   "$(tmux show -gqv @agent-tools-claude-context-bin)" # Claude statusLine adapter
#   "$(tmux show -gqv @agent-tools-turns-bin)"          bump
tmux set -g @agent-tools-state-bin          "$CURRENT_DIR/scripts/agent-state.sh"
tmux set -g @agent-tools-claude-context-bin "$CURRENT_DIR/integrations/claude-context.sh"
tmux set -g @agent-tools-turns-bin          "$CURRENT_DIR/scripts/agent-turns.sh"

# No registration step. airline's status keys are created implicitly on the first
# `status set`, and its glyphs are fixed per level (○ active, ● result, ◆
# attention) rather than picked by the caller — so the plugin has nothing to
# register at load. The scripts resolve the airline CLI themselves (via
# @airline-cli / $AIRLINE_BIN) at call time and no-op when it's absent, so this
# loader only needs to publish the setter paths above.
