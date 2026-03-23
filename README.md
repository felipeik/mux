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

Without `cmux`, `mux tab` still opens tmux sessions, and `mux list` / `mux join` can fall back to the saved state file for mux-managed entries.

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
- Names printed by `mux` are sanitized before they are written to the terminal.
- `mux restore` uses `cmux respawn-pane`, so it is aimed at `cmux` layouts that still exist but lost the terminal process behind them.
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
