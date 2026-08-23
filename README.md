# tmux-agent-tools

Surface an agent's signal in [tmux-airline](https://github.com/andrewjstryker/tmux-airline)
— at a glance, even while you're focused elsewhere. Built for a terminal-centric
agent workflow (several agents across windows). Its core is a set of thin,
provider-neutral **setters** that map *agent vocabulary → airline CLI calls*
(its supported API) or a plain tmux option. Provider integrations translate
their own payloads into that core; airline does the rendering and clearing.

Three independent signals, each matched to the airline channel that fits it:

- **Lifecycle → status badge.** A small glyph before the window name shows which
  window is **working** (`○`), **wants your input** (`◆`), or is **done** (`●`).
  Lifecycle is an *event* signal, so airline's status lane (its left-of-name
  badge stack) is the right treatment.
- **Resource pressure → health gutter.** When a provider exposes context or
  usage pressure, a severity glyph appears in the window's
  **right gutter**, **amber then red**. Both are *meters* (sustained resource
  conditions), so airline's health channel fits. The included Claude Code
  integration reports context-window and usage-limit pressure.
- **Turn counter → a widget you place.** A per-pane count of conversation turns,
  rendered as `<n>⟳` wherever your status line evaluates formats.

The three coexist on a window: a working window (`○` badge) can also be near its
context limit (red gutter glyph) and show a turn count.

## Lifecycle → status badge

`scripts/agent-state.sh` lights a pane-qualified status contributor via
`airline status set agent-<pane> <level>`. Pane qualification lets multiple
agents share a window without overwriting each other. airline's status channel
has three fixed levels; the plugin picks the *level* and airline owns the glyph:

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

`clear`/`idle` clear only the calling pane's lifecycle contributor. Provider
health is independent and is cleared by that provider's integration.

## Claude Code resource pressure → health

`integrations/claude-context.sh` adapts Claude Code's `statusLine` JSON into two
meters on airline's **health channel**. Each pane contributes its own `ctx-<pane>`
and `usage-<pane>` keys; airline reduces all health contributors to the worst
severity and shows one gutter glyph:

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
set -g @agent-tools-context-alert  75    # default 80
set -g @agent-tools-context-stress 92    # default 90
set -g @agent-tools-usage-alert    70    # default 80
set -g @agent-tools-usage-stress   85    # default 90
```

Why a meter and not a meter *widget*: Claude already shows context and usage in
the pane — but only when you're focused there, which is exactly when you don't
need tmux to tell you. The one moment they matter across windows is when a window
is *nearing a ceiling*, and that's an attention signal — `alert`/`stress`,
airline's existing resource-pressure vocab (the same it uses for battery and CPU).

Both are exposed through Claude Code's **statusLine** command, so the integration
is wired there rather than pretending its payload is a provider-neutral format.

## Turn counter → a widget you place

There's a clean split:

- **This plugin owns the value.** A per-turn hook calls `scripts/agent-turns.sh`,
  which keeps a count in the **pane-scoped** option `@agent-tools-turns`.
- **You own the rendering.** The counter is a plain tmux format that references
  `@agent-tools-turns` — a *regular widget you place yourself*. There's no special
  API: it works as an airline segment, with vanilla `status-right`, or anywhere
  a tmux format is evaluated.

Because `@agent-tools-turns` is pane-scoped, tmux resolves it against the **active
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

Render `@agent-tools-turns` wherever your status line evaluates formats.

**With tmux-airline** — a segment is just a public `@airline-segment-<slot>`
option you set with `set -g`; airline owns the chevrons and the tier background,
you own the slot and the format. There are six slots (`left-out`/`mid`/`in`,
`right-in`/`mid`/`out`):

```sh
# right-side inner slot showing "<n>⟳", blank when there's no counter
set -g @airline-segment-right-in '#{?@agent-tools-turns, #{@agent-tools-turns}⟳,}'
```

The value is a normal tmux format, so the dynamic `#{@agent-tools-turns}` stays live,
and you can style it with airline's theme color options:

```sh
set -g @airline-segment-right-in '#{?@agent-tools-turns,#[fg=#{@airline-emphasized}] #{@agent-tools-turns}⟳,}'
```

Edit the option to change it, `set -gu @airline-segment-right-in` to drop it, or
`airline segment show` to inspect the slots. (A layout is the durable way to own
the whole arrangement; a bare `set -g` is fine for one slot.)

**Without tmux-airline** — append the same format to `status-right` directly:

```sh
set -ga status-right '#{?@agent-tools-turns, #{@agent-tools-turns}⟳,}'
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
- [`jq`](https://jqlang.github.io/jq/) — **only** for the Claude Code health
  integration, which reads Claude's statusLine JSON. Without it the integration
  passes the JSON through unchanged, warns once, and skips the health update.
  The provider-neutral lifecycle and turn setters need no JSON and no jq.

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
"$(tmux show -gqv @agent-tools-state-bin)"          needs-input
"$(tmux show -gqv @agent-tools-turns-bin)"          bump
"$(tmux show -gqv @agent-tools-claude-context-bin)" # Claude statusLine adapter
```

Every plugin-owned tmux option uses the project namespace `@agent-tools-*`.
The former `@agent-state-*`, `@agent-context-*`, `@agent-usage-*`, and
`@agent-turns` names are intentionally not read as compatibility aliases.

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

## Wiring Claude Code

Add hooks to `~/.claude/settings.json` that translate Claude lifecycle events
into the neutral setters. Commands resolve the published paths at runtime, so
the configuration does not assume a TPM installation directory:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" working; fi" },
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-turns-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" bump; fi" }
    ] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" working; fi" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" needs-input; fi" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" done; fi" }] }],
    "SessionStart":     [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" clear; fi" },
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-turns-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" reset; fi" },
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-claude-context-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" clear; fi" }
    ] }],
    "SessionEnd":       [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" clear; fi" },
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-turns-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" reset; fi" },
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-claude-context-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" clear; fi" }
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
- `SessionStart`/`SessionEnd` explicitly clear each independent signal owned by
  the session, so one setter never has to know about another.

For **health** (context + usage), add the Claude adapter as your `statusLine`
command. It reports each severity on airline's health channel and passes the
JSON through unchanged, so it can precede your existing formatter:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bin=\"$(tmux show -gqv @agent-tools-claude-context-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\"; else cat; fi | your-status-line-command"
  }
}
```

If you don't have a status line, drop the pipe (Claude will show the raw JSON, or
append a formatter of your choice). statusLine is singular in Claude Code, so
this *augments* rather than replaces — the passthrough is what lets it coexist
with your existing one.

Outside tmux, all commands are silent no-ops (the statusLine mode still passes
its JSON through), so the wiring is safe in any context.

## Wiring Codex

Codex exposes the lifecycle events needed for the neutral lifecycle and turn
signals. Add the following to `~/.codex/hooks.json`:

```json
{
  "description": "Surface Codex lifecycle state in tmux-airline.",
  "hooks": {
    "SessionStart": [{
      "matcher": "startup|clear",
      "hooks": [
        { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" clear; fi" },
        { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-turns-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" reset; fi" }
      ]
    }],
    "UserPromptSubmit": [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" working; fi" },
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-turns-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" bump; fi" }
    ] }],
    "PermissionRequest": [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" needs-input; fi" }
    ] }],
    "PostToolUse": [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" working; fi" }
    ] }],
    "Stop": [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" done; fi" }
    ] }],
    "SessionEnd": [{ "hooks": [
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-state-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" clear; fi" },
      { "type": "command", "command": "bin=\"$(tmux show -gqv @agent-tools-turns-bin 2>/dev/null)\"; if [ -n \"$bin\" ]; then \"$bin\" reset; fi" }
    ] }]
  }
}
```

Codex sends JSON on stdin; these setters deliberately ignore it and emit no
stdout. Use `/hooks` in Codex to review and trust the command hooks; see the
[official Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).
Codex's hook payload does not currently expose stable context-window or
usage-limit percentages, so this integration supports lifecycle and turns but
not health.

## Tests

[bats](https://github.com/bats-core/bats-core) under `test/`, plain core bats.
The pure mappings are unit-tested; the CLI/tmux writes are checked against a fake
`airline` / `tmux` on `PATH` (airline selected via `AIRLINE_BIN`) that logs its
arguments.

```bash
make test     # bats test
make lint     # shellcheck, if installed
```
