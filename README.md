# tmux-agent-tools

Surface an agent's signal in [tmux-airline](https://github.com/andrewjstryker/tmux-airline)
— at a glance, even while you're focused elsewhere. Built for a terminal-centric
agent workflow (several agents across windows), but it knows nothing about any
specific agent: it's a set of thin **setters** that map *agent vocabulary →
airline CLI calls* (its supported API) or a plain tmux option. airline does the
rendering and clearing.

Three independent signals, each matched to the airline channel that fits it:

- **Lifecycle → status badge.** A small glyph after the window name shows which
  window is **working** (`○`), **wants your input** (`◆`), or is **done** (`●`).
  Lifecycle is an *event* signal, so airline's status lane (its right-of-name
  badge stack) is the right treatment.
- **Resource pressure → health gutter.** As an agent's **context window** fills —
  or its **usage limit** approaches — a severity glyph appears in the window's
  **left gutter**, **amber then red**. Both are *meters* (sustained resource
  conditions), so airline's health channel fits — and unlike Claude's own in-pane
  displays, they're visible across windows when you're *not* focused there.
- **Turn counter → a widget you place.** A per-pane count of conversation turns,
  rendered as `<n>⟳` wherever your status line evaluates formats.

The three coexist on a window: a working window (`○` badge) can also be near its
context limit (red gutter glyph) and show a turn count.

## Lifecycle → status badge

`scripts/agent-state.sh` lights the `agent` status key via `airline status set
agent <level>`. airline's status channel has three fixed levels, each with its
own glyph and color — the plugin picks the *level*, airline owns the glyph:

| State | airline level | Badge | In the window list |
| ----- | ------------- | ----- | ------------------ |
| `working` | `active` | `○` amber | a running system to watch |
| `needs-input` | `attention` | `◆` amber | wants your input |
| `done` | `result` | `●` green | finished well (clears when you view & leave) |
| `idle` / `clear` | — | — | no badge |

`done` is set **`--transient`**, so airline clears the badge once you've focused
the window and moved on — the one transition this plugin can't observe.
`working`/`needs-input` are persistent: the agent's own lifecycle supersedes them
(working → done/needs-input; needs-input → working when you re-engage).

> There's no `error` state: airline's status channel has no critical/red level
> (`result` outranks `active`; there's nothing above `attention`). A run that
> ends badly is still "the agent wants you" — wire it to `needs-input`.

`clear`/`idle` also clear **both** health keys this plugin drives (`ctx` and
`usage`), so a session reset wipes every channel at once.

## Resource pressure → health

`scripts/agent-context.sh` reports two meters on airline's **health channel**,
each under its own key (`airline health set <key> <severity>`); airline reduces
all health contributors to the worst severity and shows one gutter glyph:

**Context window** (`ctx` key) — how full the context is:

| Context used | airline severity | In the window list |
| ------------ | ---------------- | ------------------ |
| `< 80%` | — (cleared) | clean gutter |
| `≥ 80%` | `alert` (amber) | approaching capacity |
| `≥ 90%` | `stress` (red) | near capacity — needs attention |

**Usage limit** (`usage` key) — the worse of Claude's 5-hour and 7-day rate-limit
windows (Claude.ai Pro/Max only; absent otherwise, which reads as cleared):

| Usage-limit used | airline severity | In the window list |
| ---------------- | ---------------- | ------------------ |
| `< 80%` | — (cleared) | clean gutter |
| `≥ 80%` | `alert` (amber) | approaching your limit |
| `≥ 90%` | `stress` (red) | near your limit |

Each meter has its own **overridable** thresholds:

```tmux
set -g @agent-context-alert  75    # default 80
set -g @agent-context-stress 92    # default 90
set -g @agent-usage-alert    70    # default 80
set -g @agent-usage-stress   85    # default 90
```

Why a meter and not a meter *widget*: Claude already shows context and usage in
the pane — but only when you're focused there, which is exactly when you don't
need tmux to tell you. The one moment they matter across windows is when a window
is *nearing a ceiling*, and that's an attention signal — `alert`/`stress`,
airline's existing resource-pressure vocab (the same it uses for battery and CPU).

Both are exposed only to a Claude Code **statusLine** command, so
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

**With tmux-airline** — a segment is just a public `@airline-segment-<slot>`
option you set with `set -g`; airline owns the chevrons and the tier background,
you own the slot and the format. There are six slots (`left-out`/`mid`/`in`,
`right-in`/`mid`/`out`):

```sh
# right-side inner slot showing "<n>⟳", blank when there's no counter
set -g @airline-segment-right-in '#{?@agent-turns, #{@agent-turns}⟳,}'
```

The value is a normal tmux format, so the dynamic `#{@agent-turns}` stays live,
and you can style it with airline's theme color options:

```sh
set -g @airline-segment-right-in '#{?@agent-turns,#[fg=#{@airline-emphasized}] #{@agent-turns}⟳,}'
```

Edit the option to change it, `set -gu @airline-segment-right-in` to drop it, or
`airline segment show` to inspect the slots. (A layout is the durable way to own
the whole arrangement; a bare `set -g` is fine for one slot.)

**Without tmux-airline** — append the same format to `status-right` directly:

```sh
set -ga status-right '#{?@agent-turns, #{@agent-turns}⟳,}'
```

The `⟳` is just text in your format — swap it for any glyph you prefer.

## Requirements

- **tmux-airline** providing the `airline` CLI with its `status` and `health`
  channels, for the lifecycle badge and the health gutter. This plugin calls that
  CLI; airline owns the rendering, transient clearing, and `focus-events`. No
  private airline option names are touched. (The turn counter needs only a status
  line that evaluates tmux formats — airline is the worked example, but plain
  `status-right` works too.)
- `tmux` 3.0+. The `done` badge is `--transient`; airline enables `focus-events`
  itself the first time a transient signal is set, so its unfocus-clear works
  with no extra setup here.
- [`jq`](https://jqlang.github.io/jq/) — **only** for the health feature
  (`agent-context.sh`), which reads the statusLine JSON for context and usage. An
  agent speaks JSON and jq is the tool for JSON, so it's a hard dependency there
  rather than a hand-rolled parser; without it the script passes the JSON through
  untouched, warns once, and skips the health update. The lifecycle badge and
  turn counter use no JSON and need no jq.

## Install (TPM)

```tmux
# ~/.tmux.conf — load airline first so its CLI (@airline-cli) is published
# before the setters resolve it.
set -g @plugin 'andrewjstryker/tmux-airline'
set -g @plugin 'andrewjstryker/tmux-agent-tools'
run '~/.tmux/plugins/tpm/tpm'
```

At load the plugin only publishes each setter's path, so callers (hooks /
statusLine) need not hardcode any install dir — there's no registration step
(airline creates status keys on first `set` and its glyphs are fixed per level):

```sh
"$(tmux show -gqv @agent-state-bin)"   needs-input   # lifecycle (status lane)
"$(tmux show -gqv @agent-context-bin)"               # context + usage (health gutter, statusLine)
"$(tmux show -gqv @agent-turns-bin)"   bump          # turn counter (a format you place)
```

The setters reach the `airline` CLI through **`@airline-cli`** — the absolute
path airline publishes at load, which doubles as the contract for "airline is
active." There's no path-guessing, and it's resolved at call time, not load time.
`AIRLINE_BIN` overrides it for tests or a non-TPM layout.

If the lifecycle or health scripts are *invoked* without airline resolvable
(misconfigured, or loaded before airline), they print one warning per tmux server
and then no-op — so a missing dependency is visible without failing the hook on
every turn or spamming the statusLine. Wire none of the airline-backed signals
and you'll never see it. (The turn counter needs no airline — it's a plain tmux
option you render yourself.)

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
- `SessionStart`/`SessionEnd` → `clear` (resets the `agent` status lane *and*
  both health keys, `ctx` and `usage`) and `reset` (blanks the turn counter), so
  a session boundary leaves no stale signal anywhere.
- Another agent runner wires its own hooks to the same script calls.

For **health** (context + usage), add `agent-context.sh` as your `statusLine`
command. It reads the context and rate-limit percentages, reports each severity
on airline's health channel, and passes the JSON through unchanged — so pipe it
into whatever you already use for your status line:

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
