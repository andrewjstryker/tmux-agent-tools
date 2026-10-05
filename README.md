# tmux-agent-tools

See Claude Code and Codex activity in
[tmux-airline](https://github.com/andrewjstryker/tmux-airline) while you work in
another window.

- **Status:** working, waiting for permission, or finished responding.
- **Health:** Claude context-window and usage-limit pressure.
- **Problems:** failures that prevent Claude telemetry from working.
- **Turns:** a per-pane conversation counter you can place in your status bar.

Both providers support status and turns; Claude also supplies health telemetry.
Airline handles badge rendering and lifecycle behavior; see its
[signal guide](https://github.com/andrewjstryker/tmux-airline/blob/main/docs/signals.md).

## Install

Requires tmux-airline **3.x**, tmux **3.2+**, and Bash **4.3+**. Claude telemetry
also requires `jq`. Run Claude Code or Codex inside a tmux pane on the machine
where these plugins are installed.

With [TPM](https://github.com/tmux-plugins/tpm), add these before TPM's existing
`run` line in `~/.tmux.conf`, loading Airline first:

```tmux
set -g @plugin 'andrewjstryker/tmux-airline'
set -g @plugin 'andrewjstryker/tmux-agent-tools'
run '~/.tmux/plugins/tpm/tpm'
```

Reload with `tmux source-file ~/.tmux.conf`, then press **prefix + I** to install.
For an existing checkout, see [manual installation](docs/usage.md#manual-installation).

## Connect your agents

Installing the tmux plugin does not install provider hooks. Follow the setup
for each provider you use:

- **[Claude Code setup](docs/usage.md#claude-code):** install the hook configuration,
  optionally connect context/usage telemetry, and verify it.
- **[Codex setup](docs/usage.md#codex):** install and trust the hook configuration,
  then verify it.

The [usage guide](docs/usage.md) also covers the
[turn counter](docs/usage.md#show-the-turn-counter),
[health thresholds](docs/usage.md#health-thresholds), and
[troubleshooting](docs/usage.md#troubleshooting).

## Command line

Provider hooks find the plugin automatically. To also use `agent` from your
shell, run this in the checkout and put `~/.local/bin` on your `PATH`:

```sh
make install
agent help
```

See [contributing](CONTRIBUTING.md) for code boundaries and test commands.
