# mux

Standalone Bash CLI for restoring tmux-backed terminals inside cmux.

## Commands

- `mux` is an alias for `mux list`.
- `mux join <selector>` and `mux j <selector>` join an existing listed mux session without falling back to a literal tmux session name.
- `mux join` and `mux j` with no selector print the current list; in an interactive terminal they prompt for a selector, and in non-interactive contexts they exit with an error after printing the list.
- `mux t <name>` attaches or creates a tmux session with `tmux new-session -A -s <name>`.
- `mux tab <name>` does the same as `mux t <name>`.
- `mux list` shows the current mux-backed tabs in a table with numeric and letter selectors, workspace names, and tmux session names.
- `mux <selector>` such as `mux 1` or `mux a` joins the matching listed mux tab when a selector match exists.
- `mux -h`, `mux --help`, and `mux help` print usage.
- `mux save` and `mux s` rewrite the saved snapshot for all current cmux workspaces.
- `mux cleanup` lists tmux sessions that are not represented in the current live mux tree, asks for exact `yes`, and then deletes them.
- `mux cleanup --auto-approve` skips the confirmation prompt and immediately deletes the listed orphan tmux sessions.
- `mux restore` best-effort restores only saved `mux <name>` terminals in existing cmux workspaces.

## Selector Rules

- Selector matching has priority for bare numeric and letter tokens. If `1` or `a` matches a listed mux tab, `mux 1` or `mux a` joins that tab's tmux session.
- `mux join <selector>` and `mux j <selector>` use the same numeric and letter selector matching as `mux list`, but they never fall back to a literal tmux session name.
- If a `join` selector does not match a listed mux entry, the command exits with an error.
- `mux join` and `mux j` with no selector show the list first. They prompt only in interactive terminals; otherwise they print the list and then exit with an error.
- Bare `mux <token>` session launching is deprecated. If the token does not match a listed selector, mux prints usage instead of creating a tmux session.
- `mux t <name>` and `mux tab <name>` always treat the argument as a literal session name, so `mux t 1`, `mux t a`, and `mux tab 1` are valid.

## Restore Rules

- Only terminals titled `mux <name>` are persisted and restored.
- Browser surfaces are ignored.
- Non-tmux terminals such as `lazygit` are ignored.
- Restore matches workspaces by title and targets the existing terminal surface in the saved pane position.
- Restore uses `cmux respawn-pane`, so it is intended for panes whose terminal process was lost while the cmux layout survived.
- Restore reuses an explicit launch command and keeps the canonical `mux <name>` title format.

## Remote Shells

- If `cmux` is available, `mux list` reads the live `cmux tree --all --json` view.
- If `cmux` is unavailable, `mux list`, `mux join`, and selector-based joining fall back to the persisted state file.
- Launch-time auto-save is skipped silently when `cmux` or `jq` is unavailable.
- `mux cleanup` requires a live `cmux` host and does not run from the saved snapshot alone.

## Cleanup

- `mux cleanup` runs the save path first, then compares the live mux-managed session set against `tmux list-sessions`.
- Any tmux session not represented in the current live mux tree is treated as an orphan and listed for deletion.
- The interactive form deletes sessions only after exact `yes`.
- `--auto-approve` is the only non-interactive bypass.

## State File

By default, state is stored at `${XDG_STATE_HOME:-$HOME/.local/state}/mux/state.json`.

Set `MUX_STATE_FILE` to override the path.
