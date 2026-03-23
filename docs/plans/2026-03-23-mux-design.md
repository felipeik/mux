# Mux Design

**Goal**

Build a small CLI app named `mux` for macOS that works alongside `cmux` and provides:

- `mux tab <name>` to open or attach a named tmux session with `tmux new-session -A -s <name>`
- `mux persist` to rewrite a snapshot of all current cmux workspaces
- `mux restore` to best-effort reopen only terminals that were launched as `mux tab <name>`

**Scope**

- Persist all current cmux workspaces by workspace title
- Ignore browser surfaces entirely during restore
- Ignore non-restorable terminal tabs such as `lazygit`, `codex`, or any terminal that does not match `mux tab <name>`
- Do not rearrange windows, workspaces, panes, tabs, or browser state
- Restore should be best effort and continue on per-surface failures

**Architecture**

`mux` will be a standalone Bash CLI that shells out to `cmux`, `tmux`, and `jq`.

`persist` will call `cmux tree --all --json`, extract workspaces and terminal surfaces, and write a single JSON state file. The state file will contain only the minimal data needed for restore:

- workspace title
- terminal surface title
- pane index
- surface index within pane
- parsed `mux tab <name>` session name when recognizable

`restore` will read the saved state file and:

1. find currently open workspaces by title
2. for each saved restorable terminal entry, find the current terminal surface at the saved pane position
3. respawn that existing surface with `mux tab <name>`
4. skip entries whose workspace or surface no longer exists

Unknown or unmatched entries are skipped silently or logged as informational messages.

**Detection Model**

The only restorable terminals are ones whose title clearly matches the command pattern `mux tab <name>`. This avoids brittle process inference and keeps restore deterministic.

If a user wants a terminal to survive cmux crashes, that terminal should be started through `mux tab <name>`, which delegates durability to tmux.

**Error Handling**

- Missing `cmux`, `tmux`, or `jq` exits with a clear error
- Missing state file during `restore` exits cleanly with instructions to run `mux persist`
- Missing workspace during restore is skipped
- Failed respawns are logged and restore continues

**Testing**

The CLI will be implemented test-first with shell tests that stub `cmux` and `tmux` via `PATH`.

Tests will cover:

- `mux tab <name>` uses `tmux new-session -A -s <name>`
- `persist` writes only recognized `mux tab <name>` entries
- `persist` rewrites the full state file
- `restore` skips non-restorable entries
- `restore` respawns recognized entries in matching workspaces by name
- `restore` is best effort when one workspace or pane action fails
