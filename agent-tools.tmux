#!/usr/bin/env bash
# tmux-agent-tools — TPM entry point.
#
# A small toolkit that surfaces agent signal in the tmux-airline window list and
# status line. Three independent, agent-agnostic setters, each driven through a
# supported API (airline's CLI, or a plain tmux option) so no private option
# names are touched:
#
#   * agent-state.sh   <state>  lifecycle      -> a status badge (a glyph after
#                                                 the window name) at airline's
#                                                 active/result/attention level.
#                                                 Event signal.
#   * agent-context.sh          context+usage  -> a severity glyph in the window's
#                                                 left health gutter (airline
#                                                 health), wired as a Claude Code
#                                                 statusLine command. Meter signal.
#   * agent-turns.sh   <cmd>    turn counter   -> a per-pane count in the
#                                                 @agent-turns pane option, which
#                                                 you render wherever your status
#                                                 line evaluates formats.
#
# The three are independent and coexist: a working window (○ active badge) can
# also be near its context limit (red gutter glyph) and show a turn count. None
# of them knows about any specific agent — they map agent vocabulary -> airline
# CLI calls / a tmux option; see the README for the Claude Code wiring.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Publish each setter's path so agent hooks / statusLine need not hardcode the
# install dir:
#   "$(tmux show -gqv @agent-state-bin)"   needs-input   # lifecycle (status lane)
#   "$(tmux show -gqv @agent-context-bin)"               # context   (health gutter, statusLine)
#   "$(tmux show -gqv @agent-turns-bin)"   bump          # turn counter (a format you place)
tmux set -g @agent-state-bin   "$CURRENT_DIR/scripts/agent-state.sh"
tmux set -g @agent-context-bin "$CURRENT_DIR/scripts/agent-context.sh"
tmux set -g @agent-turns-bin   "$CURRENT_DIR/scripts/agent-turns.sh"

# No registration step. airline's status keys are created implicitly on the first
# `status set`, and its glyphs are fixed per level (○ active, ● result, ◆
# attention) rather than picked by the caller — so the plugin has nothing to
# register at load. The scripts resolve the airline CLI themselves (via
# @airline-cli / $AIRLINE_BIN) at call time and no-op when it's absent, so this
# loader only needs to publish the setter paths above.
