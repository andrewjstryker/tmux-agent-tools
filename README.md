# tmux-agent-tools

Surface an agent's signal in [tmux-airline](https://github.com/andrewjstryker/tmux-airline)
— at a glance, even while you're focused elsewhere. Built for a terminal-centric
agent workflow (several agents across windows), but it knows nothing about any
specific agent: it's a set of thin **setters** that map *agent vocabulary →
airline CLI calls* (its supported API) or a plain tmux option. airline does the
rendering and clearing.

Three independent signals, each matched to the airline channel that fits it:

- **Lifecycle → status badge.** A small colored `●` after the window name shows
  which window is **working**, **wants your input**, or is **done**. Lifecycle is
  an *event* signal, so a status lane (airline's right-of-name badge stack) is
  the right treatment.
- **Context pressure → health gutter.** As an agent's context window fills, a
  severity glyph appears in the window's **left gutter** — **amber then red**.
  Context is a *meter* (a sustained resource condition), so airline's health
  channel fits — and unlike Claude's own in-pane context display, it's visible
  across windows when you're *not* focused there.
- **Turn counter → a widget you place.** A per-pane count of conversation turns,
  rendered as `<n>⟳` wherever your status line evaluates formats.

The three coexist on a window: a working window (cyan `●` badge) can also be near
its context limit (red gutter glyph) and show a turn count.

## Lifecycle → status badge

`scripts/agent-state.sh` lights the `agent` status lane (registered once at load)
with a palette token via `airline status set agent <token>`:

| State | airline token | Color | In the window list |
| ----- | ------------- | ----- | ------------------ |
| `working` | `monitor` | cyan | a running system to watch |
| `needs-input` | `alert` | orange | wants your attention |
| `done` | `ok` | green | finished well (clears when you view & leave) |
| `error` | `stress` | red | finished badly |
| `idle` / `clear` | — | — | no badge |

`done` is set **`--transient`**, so airline clears the badge once you've focused
the window and moved on — the one transition this plugin can't observe.
`working`/`needs-input` are persistent: the agent's own lifecycle supersedes them
(working → done/needs-input; needs-input → working when you re-engage).

`clear`/`idle` also clear the context **health** key, so a session reset wipes
both airline channels at once.

## Context pressure → health

`scripts/agent-context.sh` reports the context fill on airline's **health
channel** under the `ctx` key (`airline health set ctx <severity>`); airline
reduces all health contributors to the worst severity and shows one gutter glyph:

| Context used | airline severity | In the window list |
| ------------ | ---------------- | ------------------ |
| `< 80%` | — (cleared) | clean gutter |
| `≥ 80%` | `alert` (amber) | approaching capacity |
| `≥ 90%` | `stress` (red) | near capacity — needs attention |

The thresholds are **overridable** tmux options:

```tmux
set -g @agent-context-alert  75    # default 80
set -g @agent-context-stress 92    # default 90
```

Why a meter and not a meter *widget*: Claude already shows context usage in the
pane — but only when you're focused there, which is exactly when you don't need
tmux to tell you. The one moment it matters across windows is when a window is
*nearing capacity*, and that's an attention signal — `alert`/`stress`, airline's
existing resource-pressure vocab (the same it uses for battery and CPU).

Context usage is exposed only to a Claude Code **statusLine** command, so
`agent-context.sh` is wired there (see below), not as a hook.

## Turn counter → a widget you place

There's a clean split:

- **This plugin owns the value.** A per-turn hook calls `scripts/agent-turns.sh`,
  which keeps a count in the **pane-scoped** option `@agent-turns`.
- **You own the rendering.** The counter is a plain tmux format that references
  `@agent-turns` — a *regular widget you place yourself*. There's no special
  API: it works as an airline segment, with vanilla `status-right`, or anywhere
  a tmux format is evaluated.

Because `@agent-turns` is pane-scoped, tmux resolves it against the **active
pane**, so the widget shows the turn count of the pane you're looking at and is
blank when that pane isn't running an agent.

`agent-turns.sh` maintains the counter:

| Command | Effect |
| ------- | ------ |
| `bump` | increment the active pane's counter (unset → 1) |
| `reset` / `clear` | remove the counter (blank in the status line) |

Claude Code (like agents generally) exposes no turn count to hooks, so the plugin
maintains its own — no transcript parsing.

### Placing the widget

Render `@agent-turns` wherever your status line evaluates formats.

**With tmux-airline** — register a segment whose `--format` reads the option; you
own its side, tier, priority, and format, airline owns the chevrons and the tier
background:

```sh
# right-side inner segment showing "<n>⟳", blank when there's no counter
airline segment register agent --side right --tier inner \
  --format '#{?@agent-turns, #{@agent-turns}⟳,}'
```

The `--format` is a normal tmux format, so the dynamic `#{@agent-turns}` stays
live, and you can style it with airline's theme color options:

```sh
airline segment register agent --side right --tier inner \
  --format '#{?@agent-turns,#[fg=#{@airline-emphasized}] #{@agent-turns}⟳,}'
```

Re-register the same name to change it, `airline segment unregister agent` to
drop it, or `airline segment list` to inspect the stack.

**Without tmux-airline** — append the same format to `status-right` directly:

```sh
set -ga status-right '#{?@agent-turns, #{@agent-turns}⟳,}'
```

The `⟳` is just text in your format — swap it for any glyph you prefer.

## Requirements

- **tmux-airline** providing the `airline` CLI with its `status` and `health`
  channels, for the lifecycle badge and context gutter. This plugin calls that
  CLI; airline owns the rendering, transient clearing, and `focus-events`. No
  private airline option names are touched. (The turn counter needs only a status
  line that evaluates tmux formats — airline is the worked example, but plain
  `status-right` works too.)
- `tmux` 3.0+. The `done` badge is `--transient`; airline enables `focus-events`
  itself the first time a transient signal is set, so its unfocus-clear works
  with no extra setup here.

## Install (TPM)

```tmux
# ~/.tmux.conf — load airline first: this plugin registers its 'agent' lane
# against the CLI airline publishes in @airline-cli at load.
set -g @plugin 'andrewjstryker/tmux-airline'
set -g @plugin 'andrewjstryker/tmux-agent-tools'
run '~/.tmux/plugins/tpm/tpm'
```

At load the plugin registers the `agent` status lane and publishes each setter's
path, so callers (hooks / statusLine) need not hardcode any install dir:

```sh
"$(tmux show -gqv @agent-state-bin)"   needs-input   # lifecycle (status lane)
"$(tmux show -gqv @agent-context-bin)"               # context   (health gutter, statusLine)
"$(tmux show -gqv @agent-turns-bin)"   bump          # turn counter (a format you place)
```

The plugin reaches the `airline` CLI through **`@airline-cli`** — the absolute
path airline publishes at load, which doubles as the contract for "airline is
active." There's no path-guessing: if the option is unset, airline isn't loaded
and the status-lane registration is skipped (the turn counter still works, since
it's a plain tmux option). `AIRLINE_BIN` overrides it for tests or a non-TPM
layout.

## Wiring an agent: Claude Code

`tmux-agent-tools` is agent-agnostic; Claude Code is one consumer. Add hooks to
`~/.claude/settings.json` that call the setters on lifecycle events. All three
signals share the same `SessionStart`/`SessionEnd` events — list their commands
under one event's `hooks` array:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [
      { "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-state.sh working" },
      { "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-turns.sh bump" }
    ] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-state.sh working" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-state.sh needs-input" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-state.sh done" }] }],
    "SessionStart":     [{ "hooks": [
      { "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-state.sh clear" },
      { "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-turns.sh reset" }
    ] }],
    "SessionEnd":       [{ "hooks": [
      { "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-state.sh clear" },
      { "type": "command", "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-turns.sh reset" }
    ] }]
  }
}
```

- `UserPromptSubmit` → `working` (lifecycle) and `bump` (one increment per prompt
  is exactly one turn); `Notification` → `needs-input`; `Stop` → `done`. Each
  lifecycle state supersedes the last, so transitions need no explicit clearing.
- `PostToolUse` → `working` is optional but recommended: it flips a window back
  to `working` when the agent resumes after you grant a permission (the one
  resume that isn't a prompt). It fires per tool call — cheap, idempotent.
- `SessionStart`/`SessionEnd` → `clear` (resets the `agent` status lane *and* the
  `ctx` health key) and `reset` (blanks the turn counter), so a session boundary
  leaves no stale signal anywhere.
- Another agent runner wires its own hooks to the same script calls.

For **context pressure**, add `agent-context.sh` as your `statusLine` command. It
reads the context percentage, reports the severity on airline's health channel,
and passes the JSON through unchanged — so pipe it into whatever you already use
for your status line:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.tmux/plugins/tmux-agent-tools/scripts/agent-context.sh | your-status-line-command"
  }
}
```

If you don't have a status line, drop the pipe (Claude will show the raw JSON, or
append a formatter of your choice). statusLine is singular in Claude Code, so
this *augments* rather than replaces — the passthrough is what lets it coexist
with your existing one.

Outside tmux, all three scripts are silent no-ops (`agent-context.sh` still
passes the JSON through), so the wiring is safe in any context.

## Tests

[bats](https://github.com/bats-core/bats-core) under `test/`, plain core bats.
The pure mappings are unit-tested; the CLI/tmux writes are checked against a fake
`airline` / `tmux` on `PATH` (airline selected via `AIRLINE_BIN`) that logs its
arguments.

```bash
make test     # bats test
make lint     # shellcheck, if installed
```
