# Usage guide

[Install the tmux plugin](../README.md#install) first, then configure
[Claude Code](#claude-code), [Codex](#codex), or both.

## Check the installation

In a shell inside tmux, run:

```sh
tmux show -gqv @agent-cli
tmux show -gqv @airline-cli
"$(tmux show -gqv @agent-cli)" version
"$(tmux show -gqv @airline-cli)" version
```

The first two commands should print executable paths; the last two should print
versions. Airline must report `3.x.x`. Hook commands use these handles, so you
do not need to install the optional `agent` shell command for hooks to work.

## Claude Code

### Install lifecycle hooks

Open [`examples/claude-settings.json`](../examples/claude-settings.json).
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

Open [`examples/codex-hooks.json`](../examples/codex-hooks.json).
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
The following shell commands place the active pane's count in Airline's
right-inner segment, replacing that slot's existing content:

```sh
tmux set -g @airline-segment-right-in '#{?@agent-tools-turns, #{@agent-tools-turns}⟳,}'
"$(tmux show -gqv @airline-cli)" session apply
```

Run `session apply` in each session where you want the override applied. The count
text is blank when unset; a configured segment can still retain spacing and
chevrons. To remove the override, unset the option and reapply:

```sh
tmux set -gu @airline-segment-right-in
"$(tmux show -gqv @airline-cli)" session apply
```

For a persistent arrangement, add the format to your Airline layout; see
[Airline layouts](https://github.com/andrewjstryker/tmux-airline/blob/main/docs/layouts.md).
For a plain tmux status line, use:

```sh
tmux set -ga status-right '#{?@agent-tools-turns, #{@agent-tools-turns}⟳,}'
```

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
`TMUX_PANE`. Missing or incompatible Airline installations warn once per tmux
server and skip Airline updates. `AIRLINE_BIN` can explicitly select another
Airline executable for a custom installation.

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

Reload with `tmux source-file ~/.tmux.conf`, then follow the provider setup above.
