# mux

`mux` is a tiny Bash CLI that sits next to `cmux` and keeps named `tmux` sessions easy to reopen.

This exists because `cmux` sometimes hangs or crashes, especially while browsing around the `cmux` browser UI. When that happens, force-quitting should not mean losing track of which tmux session belonged in which tab. `mux` gives those tabs stable tmux session names, remembers which `cmux` tab/pane was attached to which tmux session, and makes it easy to rejoin the same agent session later, including over SSH from a phone or iPad.

This project was fully vibe-coded. Read the script, use it if it fits your workflow, and assume responsibility for running it in your own environment.

## Why use it

- Open named `tmux` sessions from inside `cmux` with a consistent tab title format.
- Remember which tabs were attached to which named tmux sessions.
- Reattach those tabs to the remembered tmux sessions after a crash, hang, or force-quit.
- Rejoin an existing session later with `mux join`, including from a remote shell.
- See mux-managed tabs and other live tmux sessions in one selector table.

## Requirements

- `bash`
- `tmux`
- `jq`
- `cmux` for full tab-to-session snapshot and restore integration

Without a usable live `cmux` tree, `mux tab` still opens tmux sessions, and `mux list` / `mux join` can fall back to the saved state file for mux-managed entries.

`mux init` configures Claude Code and Codex hooks so those CLIs can notify `cmux` from plain `cmux` shells and from `tmux` running inside `cmux`. `mux uninstall` removes the hook entries that `mux` added.

If you need to route notifications from a Docker sandbox back into `cmux`, see
[`docs/sandbox-cmux-notifications.md`](docs/sandbox-cmux-notifications.md) for
the reusable pattern, topology guidance, and failure modes.

To scaffold a bare-bones Claude Docker sandbox into another project, use:

```bash
bin/install-claude-sandbox /path/to/project
```

The installer creates a minimal `sandbox/` plus project-local Claude hooks. It
supports `cmux > sandbox` and `cmux > tmux > sandbox` notification delivery,
includes a host-backed `bd` shim, supports optional extra read-only mounts from
`sandbox/.env`, supports optional extra allowed host ports from `sandbox/.env`,
and does not add broader host command shims such as `git` or `swift`.

## Installation

There is no Homebrew package right now.

### Option 1: clone the repo and symlink it

This is the easiest way to keep the script up to date if you pull new changes later.

```bash
git clone https://github.com/felipeik/mux.git
cd mux
chmod +x bin/mux
mkdir -p ~/.local/bin
ln -sf "$(pwd)/bin/mux" ~/.local/bin/mux
```

If `~/.local/bin` is not already in your `PATH`, add this to your shell config:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload your shell and verify:

```bash
mux --help
```

### Option 2: install the single script directly

If you do not want a full clone, you can download just the script:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/felipeik/mux/main/bin/mux -o ~/.local/bin/mux
chmod +x ~/.local/bin/mux
```

Then make sure `~/.local/bin` is in your `PATH` and run:

```bash
mux --help
```

## Global agent hooks

Install the supported global hooks:

```bash
mux init
```

Install only one integration:

```bash
mux init claude
mux init codex
```

Choose a scope for Claude:

```bash
mux init claude --scope project
mux init claude --scope local-project
```

Remove hooks again:

```bash
mux uninstall
mux uninstall claude
mux uninstall codex
mux uninstall claude --scope project
```

Behavior:

- `mux init claude` defaults to user scope and merges hooks into `~/.claude/settings.json`.
- `mux init claude --scope project` writes to `.claude/settings.json` in the current project.
- `mux init claude --scope local-project` writes to `.claude/settings.local.json` in the current project.
- `mux init codex` writes `~/.codex/hooks.json` and enables `codex_hooks = true` in `~/.codex/config.toml`.
- `mux uninstall claude` removes `mux`-managed Claude hooks from all three Claude scopes: `~/.claude/settings.json`, `.claude/settings.json`, and `.claude/settings.local.json`.
- `mux uninstall claude --scope ...` removes Claude hooks only from the selected scope.
- `Codex` currently supports `--scope user` only.
- Missing apps are skipped instead of causing the command to fail.
- The installed helper lives at `~/.local/bin/mux-agent-notify`.
- Inside plain `cmux`, the helper uses `cmux notify`.
- Inside `tmux` within `cmux`, the helper uses `tmux` OSC passthrough so notifications still reach `cmux`.
- `mux init` and `mux uninstall` print the paths they touched so you can see exactly where the hooks were created or removed.

## Typical workflow

Start named tabs from inside `cmux`:

```bash
mux tab claude-main
mux tab codex-api
mux tab backend
```

See what is available:

```bash
mux list
```

Example output:

```text
#  Key  Workspace  Session
-  ---  ---------  -------
1  a    Main       claude-main
2  b    Main       codex-api
3  c    Main       backend
```

Join an existing session by selector:

```bash
mux join 1
mux join b
```

Or run `mux join` with no selector in an interactive terminal and pick from the list.

Save the current tab-to-session snapshot:

```bash
mux save
```

After a `cmux` crash or force-quit, reattach the remembered tmux sessions to the matching panes:

```bash
mux restore
```

If you SSH into the same machine from your phone or iPad, `mux list` plus `mux join` is the fast path back into the same agent session without guessing the tmux session name.

## Commands

- `mux`, `mux help`, `mux h`, `mux -h`, `mux --help`
  Print usage.
- `mux init`
  Install the supported global Claude Code and Codex notification hooks, skipping any app that is not installed.
- `mux init claude`
  Merge the Claude Code notification hooks into `~/.claude/settings.json`.
- `mux init claude --scope project`
  Merge the Claude Code notification hooks into `.claude/settings.json` in the current project.
- `mux init claude --scope local-project`
  Merge the Claude Code notification hooks into `.claude/settings.local.json` in the current project.
- `mux init codex`
  Install Codex hooks into `~/.codex/hooks.json` and enable `codex_hooks` in `~/.codex/config.toml`.
- `mux uninstall`
  Remove the `mux`-managed Claude Code hooks from all Claude scopes in the current project context, and remove the `mux`-managed Codex hooks from the user scope.
- `mux uninstall claude`
  Remove the `mux`-managed Claude Code hook entries from all Claude scopes in the current project context.
- `mux uninstall claude --scope project`
  Remove the `mux`-managed Claude Code hook entries only from `.claude/settings.json` in the current project.
- `mux uninstall codex`
  Remove the `mux`-managed Codex hook entries from `~/.codex/hooks.json` and disable `codex_hooks` when no hooks remain.
- `mux tab <name>` and `mux t <name>`
  Create or attach to a literal tmux session with `tmux new-session -A -s <name>`, rename the current `cmux` tab to `mux <name>`, and best-effort refresh the saved tab-to-session snapshot first when `cmux` and `jq` are available.
- `mux list` and `mux l`
  Show mux-managed tabs plus any other live tmux sessions not already represented by the mux snapshot.
- `mux join <selector>` and `mux j <selector>`
  Join an existing listed session by numeric or letter selector.
- `mux join` and `mux j`
  Print the list first; in an interactive terminal they prompt for a selector, and in non-interactive mode they exit with an error after printing the list.
- `mux save` and `mux s`
  Save the current mux-managed tab, pane, and tmux-session mapping to the state file.
- `mux restore` and `mux r`
  Best-effort reattach saved `mux <name>` terminals to the remembered tmux sessions in matching existing workspaces.
- `mux cleanup`
  Show orphan tmux sessions that are no longer represented by the live mux tree, ask for exact `yes`, then delete them.
- `mux cleanup --auto-approve`
  Delete the listed orphan tmux sessions without prompting.

## Important behavior

- Only terminals titled `mux <name>` are included in the saved snapshot and restore flow.
- Browser surfaces are ignored.
- Non-tmux commands such as `lazygit` are ignored by save/restore.
- `mux join` only accepts selectors from the current list. It does not fall back to treating the argument as a literal tmux session name.
- Bare commands like `mux 1` or `mux backend` are invalid on purpose. Use `mux join <selector>` or `mux tab <name>`.
- `mux tab <name>` rejects session names that contain terminal control characters.
- `mux init` writes user-level config under `~/.claude/`, `~/.codex/`, and `~/.local/bin/`; it merges supported hook entries instead of replacing unrelated settings.
- `mux init` and `mux uninstall` only add or remove `mux-agent-notify` hook entries. They keep unrelated hook settings intact.
- Names printed by `mux` are sanitized before they are written to the terminal.
- `mux restore` uses `cmux respawn-pane`, so it is aimed at `cmux` layouts that still exist but lost the terminal process behind them.
- `mux save` refuses to overwrite the saved snapshot when `cmux tree --all --json` is unavailable or empty.
- `mux restore` requires both a reachable live `cmux` tree and a non-empty saved snapshot file.
- `mux` does not replace `cmux`'s own layout handling. It only remembers which tmux session belonged to which saved mux-managed terminal.
- `mux cleanup` can kill tmux sessions. Read the list before approving it.

## State file

By default, state is stored at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/mux/state.json
```

Set `MUX_STATE_FILE` to override the path.

## License and disclaimer

This repo is licensed under the MIT license. You can use it, copy it, modify it, redistribute it, and sell it.

It is provided strictly on an "as is" basis, without warranty or support. If it reattaches the wrong tmux session, fails to restore your tabs the way you expect, or breaks your workflow, that risk is yours. Read the code before using it anywhere important.
