# Usage guide

[Install the tmux plugin](README.md#install) first, then configure
[Claude Code](#claude-code), [Codex](#codex), or both.

## Check the installation

In a shell inside tmux, run:

```sh
tmux show -gqv @agent-cli
tmux show -gqv @airline-cli
"$(tmux show -gqv @agent-cli)" version
"$(tmux show -gqv @airline-cli)" version
```

The Agent handle should print an executable path. If Airline is loaded, its
handle should also print a path and its version should be `3.x.x`. For a
standalone turn widget, skip the Airline commands. Hook commands use the
published handles, so the optional `agent` shell command is not required.

## Initialization

The plugin loader initializes Agent in its current tmux session. Operational
commands also initialize on first use in a session. Initialization checks
Airline's version and registers the widget directory only when `@airline-cli`
is published. It never starts Airline or searches for an executable on `PATH`.

The session option `@agent-tools-init` records that setup was attempted, including
when Airline is absent or incompatible. Later invocations reuse that result.
Turn counting remains available without Airline. The session option
`@agent-tools-airline-cli` records the CLI accepted during initialization;
Agent stops reporting signals if Airline withdraws or changes its published handle.

After loading, upgrading, or repairing Airline, reset and repeat initialization:

```sh
"$(tmux show -gqv @agent-cli)" init
# Or, with the optional shell command installed:
agent init
```

`init` clears the marker and performs setup again for the current session. It
preserves turn counts and existing signals. Reloading `agent.tmux` does the same.
`help`, `version`, and standalone widget formatting do not initialize anything.

## Claude Code

### Install lifecycle hooks

Open [`examples/claude-settings.json`](examples/claude-settings.json).
If `~/.claude/settings.json` does not exist, create its parent directory and copy
the example there. Otherwise, merge the example's `hooks` object into that file:
add missing event entries and append to existing event arrays. Preserve your
other settings and hooks. Install each Agent hook once to avoid counting turns
twice. The example includes all lifecycle hooks, but no `statusLine` setting.

Start a new Claude Code session inside tmux and inspect `/hooks` to confirm the
commands are loaded. See Claude's [hook reference](https://code.claude.com/docs/en/hooks)
for settings locations and hook controls.

### Add context and usage telemetry (optional)

Install `jq` and confirm `jq --version` works in the environment running Claude.
Add the following top-level setting to `~/.claude/settings.json`, alongside
`hooks`. This complete example reports telemetry to Airline and displays a short
context reading in Claude:

```json
{
  "statusLine": {
    "type": "command",
    "command": "cli=\"$(tmux show -gqv @agent-cli 2>/dev/null)\"; if [ -n \"$cli\" ]; then \"$cli\" telemetry claude update; else cat; fi | jq -r '\"Context: \\(.context_window.used_percentage // 0)%\"'"
  }
}
```

If you already have a status-line formatter, preserve it: replace only the final
`jq -r '...'` in this command with your existing formatter command. Agent passes
the input JSON through to that formatter. To report to Airline without showing
text in Claude, use `cat >/dev/null` as the final command. Do not configure Agent
alone as the formatter: it would display the raw JSON.

Claude's [status-line guide](https://code.claude.com/docs/en/statusline) describes
available measurements and formatter configuration. Agent reads context usage
and the worse of the five-hour and seven-day usage percentages when supplied;
absent measurements produce no health warning.

### Verify Claude

Submit a prompt: Airline should show working, then a completed result when
Claude finishes. A tool permission request should show attention. If you enabled
telemetry, check that your Claude status line still renders. A health badge only
appears when a measurement reaches its warning threshold; inspect failures with:

```sh
"$(tmux show -gqv @airline-cli)" problem show
```

## Codex

Open [`examples/codex-hooks.json`](examples/codex-hooks.json).
Create `~/.codex/hooks.json` from it if the file does not exist. If it does,
append the example entries to the corresponding arrays under `hooks`, preserving
existing hooks. Use the corresponding location under `CODEX_HOME` if customized.
Avoid installing these same hooks in both user and project configuration, since
matching hooks from multiple sources all run.

Start Codex inside tmux, open `/hooks`, and review and trust the Agent commands.
Repeat the trust review after changing their definitions. Hooks are enabled by
default; if you previously disabled them, enable `hooks` under `[features]` in
your Codex configuration. See the official
[Codex hook guide](https://learn.chatgpt.com/docs/hooks) for trust and configuration
controls.

Submit a prompt and check for working followed by a completed result. A tool
permission request should show attention. This integration supplies status and
turn counts for Codex; it does not supply Codex health telemetry.

## Show the turn counter

Each prompt hook increments the calling pane's `@agent-tools-turns` option.
The `agent-turns` widget renders that value as `<n>⟳` using a native tmux format;
it has no background process or dependency on Airline. An unset count renders
no text.

### With Airline

Agent's loader registers its widget directory in the current Airline session.
Check registration from that session with:

```sh
"$(tmux show -gqv @airline-cli)" widget describe agent-turns
```

Include the widget in an Airline layout. For example, save this as
`~/.config/airline/layouts/agent.sh` (create the directory first):

```bash
airline_layout_configure() {
  "$1" segment left-out '#S'
  "$1" segment right-in '#{E:@airline--widget-agent-turns}'
}
```

Then load it from your shell:

```sh
"$(tmux show -gqv @airline-cli)" layout load "$HOME/.config/airline/layouts/agent.sh"
```

This example replaces the current arrangement. To keep your existing layout,
add the widget reference to one of its segment declarations instead. The
containing segment retains its spacing and chevrons when the count is unset.
See [Airline layouts](https://github.com/andrewjstryker/tmux-airline/blob/main/docs/layouts.md)
for persistent layout configuration.

Catalog registration belongs to each Airline session. In an additional session,
run Agent initialization after initializing Airline and before loading the layout:

```sh
"$(tmux show -gqv @agent-cli)" init
```

### Without Airline

Load Agent normally, omitting Airline from your tmux plugin configuration.
To append the widget to a plain status line, run this once in your shell:

```sh
cli="$(tmux show -gqv @agent-cli)"
tmux set -ga status-right " $(bash "${cli%/*}/widgets/agent-turns.sh")"
```

For a persistent setup, the equivalent native format can go in `~/.tmux.conf`:

```tmux
set -ga status-right ' #{?@agent-tools-turns,#{@agent-tools-turns}⟳,}'
```

The provider hooks still maintain turns without Airline. Signal reporting is
silently skipped until Airline is loaded and you run `agent init`.

## Health thresholds

Claude context and usage meters each warn at **80%** and fail at **90%** by
default. Put overrides in `~/.tmux.conf`, then reload it:

```tmux
set -g @agent-tools-context-warn 75
set -g @agent-tools-context-fail 92
set -g @agent-tools-usage-warn 70
set -g @agent-tools-usage-fail 85
```

These are pane-owned health observations, aggregated by Airline for the window.
Inspect the current pane's observations with:

```sh
"$(tmux show -gqv @airline-cli)" health show -t "$TMUX_PANE"
```

## Commands and event mapping

Use `agent help` or, without the optional shell installation,
`"$(tmux show -gqv @agent-cli)" help` for the command reference.

| Provider event | Agent contribution |
| --- | --- |
| `UserPromptSubmit` | Working status and incremented turn count |
| `PermissionRequest` | Needs-input status |
| Claude `PostToolBatch` / Codex `PostToolUse` | Working status |
| `Stop` | Done status |
| `SessionStart` matching `startup` or `clear` | Clear provider state |
| `SessionEnd` | Clear provider state |

Claude cleanup includes telemetry; Codex cleanup covers lifecycle and turns.
Resume and compaction do not reset state with the supplied configuration.
Working, needs-input, and done map to Airline's `active`, `attention`, and
`result`. Done means the agent finished responding, not that its task succeeded.
See [Airline signals](https://github.com/andrewjstryker/tmux-airline/blob/main/docs/signals.md)
for badge priorities, result observation, acknowledgement, and recovery.

## Troubleshooting

**No activity badges:** check the published paths above, launch the provider
inside tmux, and check its hook configuration. Agent requires both `TMUX` and
`TMUX_PANE`. If Airline was loaded after Agent, run `agent init` in this session.
An incompatible or broken published Airline CLI produces a diagnostic during
initialization and disables signal reporting; run `agent init` again after fixing it.

**Hooks loaded but not running:** inspect the provider's `/hooks` controls,
including Codex trust. Restart the provider after configuration changes and
check that hook commands can find `tmux` and Bash on `PATH`.

**Turn count increases twice:** remove duplicate Agent hooks from user/project
configuration. Inspect the value with
`tmux show -pqv -t "$TMUX_PANE" @agent-tools-turns`.

**Claude telemetry is missing:** confirm the `statusLine` setting is present and
`jq` is available, then run Airline's `problem show`. Agent reports telemetry
failures under `tmux-agent-tools-claude-telemetry`. Low or absent measurements
leave the health gutter clear.

**Stale state after an interrupted session:** run these from the affected pane's
shell (omit the telemetry command for Codex):

```sh
cli="$(tmux show -gqv @agent-cli)"
"$cli" lifecycle clear
"$cli" turns clear
"$cli" telemetry claude clear
```

## Manual installation

Clone this repository to a permanent directory. Load Airline and then Agent from
`~/.tmux.conf`, replacing these paths with your checkout paths:

```tmux
run-shell /path/to/tmux-airline/airline.tmux
run-shell /path/to/tmux-agent-tools/agent.tmux
```

Omit the Airline line for a standalone turn widget. Reload with
`tmux source-file ~/.tmux.conf`, then follow the provider setup above.
