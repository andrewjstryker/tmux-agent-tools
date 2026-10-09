# tmux-agent-tools

See Claude Code and Codex activity in
[tmux-airline](https://github.com/andrewjstryker/tmux-airline) while you work in
another window.

- **Status:** working, waiting for permission, or finished responding.
- **Health:** Claude context-window and usage-limit pressure.
- **Problems:** failures that prevent Claude telemetry from working.
- **Turns:** a conversation-turn widget for Airline or a plain tmux status bar.

Both providers support status and turns; Claude also supplies health telemetry.
Airline handles badge rendering and lifecycle behavior; see its
[signal guide](https://github.com/andrewjstryker/tmux-airline/blob/main/docs/signals.md).

## Install

Requires tmux **3.2+**, Bash **4.3+**, and `jq`. Signal reporting also requires
tmux-airline **3.x**; the turn widget works without Airline. Run Claude Code or
Codex inside a tmux pane on the machine where the plugin is installed.

With [TPM](https://github.com/tmux-plugins/tpm), add these before TPM's existing
`run` line in `~/.tmux.conf`, loading Airline first:

```tmux
set -g @plugin 'andrewjstryker/tmux-airline'
set -g @plugin 'andrewjstryker/tmux-agent-tools'
run '~/.tmux/plugins/tpm/tpm'
```

Reload with `tmux source-file ~/.tmux.conf`, then press **prefix + I** to install.
Agent initializes once per session and registers its widget directory when
Airline is loaded. Run `agent init` to repeat setup after changing Airline.
For an existing checkout or a setup without Airline, see [manual installation](USAGE.md#manual-installation).

## Connect your agents

Installing the tmux plugin does not install provider hooks. Follow the setup
for each provider you use:

- **[Claude Code setup](USAGE.md#claude-code):** install the hook configuration,
  optionally connect context/usage telemetry, and verify it.
- **[Codex setup](USAGE.md#codex):** install and trust the hook configuration,
  then verify it.

The [usage guide](USAGE.md) also covers the
[turn counter](USAGE.md#show-the-turn-counter),
[health thresholds](USAGE.md#health-thresholds), and
[troubleshooting](USAGE.md#troubleshooting).

## Command line

Provider hooks find the plugin automatically. To also use `agent` from your
shell, run this in the checkout and put `~/.local/bin` on your `PATH`:

```sh
make install
agent help
```

See [contributing](CONTRIBUTING.md) for code boundaries and test commands.
