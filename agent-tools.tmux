#!/usr/bin/env bash
# tmux-agent-tools — TPM entry point.
#
# A small toolkit that surfaces agent signal in the tmux-airline window list and
# status line. Three independent, agent-agnostic setters, each driven through a
# supported API (airline's CLI, or a plain tmux option) so no private option
# names are touched:
#
#   * agent-state.sh   <state>  lifecycle      -> a colored ● status badge after
#                                                 the window name (airline status
#                                                 lane). Event signal.
#   * agent-context.sh          context fill   -> a severity glyph in the window's
#                                                 left health gutter (airline
#                                                 health), wired as a Claude Code
#                                                 statusLine command. Meter signal.
#   * agent-turns.sh   <cmd>    turn counter   -> a per-pane count in the
#                                                 @agent-turns pane option, which
#                                                 you render wherever your status
#                                                 line evaluates formats.
#
# The three are independent and coexist: a working window (cyan ● badge) can also
# be near its context limit (red gutter glyph) and show a turn count. None of
# them knows about any specific agent — they map agent vocabulary -> airline CLI
# calls / a tmux option; see the README for the Claude Code wiring.
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Publish each setter's path so agent hooks / statusLine need not hardcode the
# install dir:
#   "$(tmux show -gqv @agent-state-bin)"   needs-input   # lifecycle (status lane)
#   "$(tmux show -gqv @agent-context-bin)"               # context   (health gutter, statusLine)
#   "$(tmux show -gqv @agent-turns-bin)"   bump          # turn counter (a format you place)
tmux set -g @agent-state-bin   "$CURRENT_DIR/scripts/agent-state.sh"
tmux set -g @agent-context-bin "$CURRENT_DIR/scripts/agent-context.sh"
tmux set -g @agent-turns-bin   "$CURRENT_DIR/scripts/agent-turns.sh"

# The airline CLI's absolute path, published by airline at load in @airline-cli.
# That option is the contract for "airline is active," so we read it rather than
# probe for the binary — if it's unset, airline isn't loaded and there's nothing
# to register against (load airline before this plugin). AIRLINE_BIN overrides it
# for tests / non-TPM installs.
#
# The turn counter needs no registration here (it's a plain tmux option you
# render yourself), so a missing airline only skips the status-lane registration.
airline_bin="${AIRLINE_BIN:-$(tmux show -gqv @airline-cli)}"

# Register the 'agent' status lane once (idempotent in airline). Lifecycle states
# light this lane with a palette token; the glyph is the badge airline renders
# after the window name. airline owns transient clearing and focus-events, so the
# plugin needs no further setup.
[ -n "$airline_bin" ] && "$airline_bin" status register agent ●
