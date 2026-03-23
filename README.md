# mux

Standalone Bash CLI for restoring tmux-backed terminals inside cmux.

## Commands

- `mux tab <name>` attaches or creates a tmux session with `tmux new-session -A -s <name>`.
- `mux persist` rewrites the saved snapshot for all current cmux workspaces.
- `mux restore` best-effort restores only saved `mux tab <name>` terminals in existing cmux workspaces.

## Restore Rules

- Only terminals titled `mux tab <name>` are persisted and restored.
- Browser surfaces are ignored.
- Non-tmux terminals such as `lazygit` are ignored.
- Restore matches workspaces by title and targets the existing terminal surface in the saved pane position.
- Restore uses `cmux respawn-pane`, so it is intended for panes whose terminal process was lost while the cmux layout survived.

## State File

By default, state is stored at `${XDG_STATE_HOME:-$HOME/.local/state}/mux/state.json`.

Set `MUX_STATE_FILE` to override the path.
