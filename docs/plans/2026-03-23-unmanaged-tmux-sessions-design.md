# Unmanaged Tmux Sessions Design

**Date:** 2026-03-23

## Goal

Allow `mux list` and `mux join` to surface live tmux sessions that are not present in the mux snapshot so users can still reattach after accidentally closing a `cmux` tab.

## Selected Approach

Append unmanaged tmux sessions after mux-managed entries in the existing `mux list` table and make `mux join <selector>` resolve selectors against that combined list.

## Behavior

- Mux-managed entries remain first and keep their current ordering based on workspace title, pane index, and surface index.
- Live tmux sessions not already represented by a mux-managed entry are appended after the mux-managed block.
- Appended unmanaged rows keep the current table shape and use `-` as the workspace value because there is no live mux workspace mapping for them.
- `mux join <selector>` stays selector-only. It may target either a mux-managed row or an appended unmanaged row.
- `mux join <literal-name>` still does not fall back to a direct tmux session name. Only listed selectors are valid.
- When `cmux` is unavailable, the mux-managed portion still comes from the saved state file, and the unmanaged portion still comes from live `tmux list-sessions` when `tmux` is available.

## Constraints

- Do not duplicate sessions already represented by mux-managed entries.
- Keep the list output as a single table so selector numbering and lettering remain straightforward.
- Preserve current non-interactive and interactive `mux join` behavior aside from the larger selectable set.

## Testing

- Add a list regression showing appended unmanaged rows after mux-managed rows.
- Add a join regression showing a selector can attach to an appended unmanaged row.
- Keep the existing no-literal-fallback guarantee.
