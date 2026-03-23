# Mux List Simplification Design

**Goal**

Simplify `mux list` so it prints only the selectors and the mux session mapping, without redundant title data or instructional decorations.

**Scope**

- Remove the `Title` column from `mux list`.
- Keep the numeric selector, letter selector, workspace, and session columns.
- Remove the deprecated `(*)` selector-conflict markers.
- Remove all list helper and instructional lines so `mux list` prints only the table.
- Update README examples and shell tests to match the simplified output.

**Architecture**

The change stays inside the existing single-file Bash CLI and its shell-based test suite.

`cmd_list` will continue to use the current mux entry discovery and ordering logic, but it will render a narrower four-column table. The selector-conflict formatting path becomes unnecessary once the `(*)` marker is removed, so the list renderer can print the raw selector values directly in both the live `cmux` path and the saved-state fallback path.

**Output Model**

- `mux list` prints a header row plus one row per mux-managed entry.
- The visible columns are index, key, workspace, and tmux session name.
- `mux list` does not print helper text before or after the table.
- `mux list` does not print `(*)` markers anywhere.

**Non-Goals**

- No selector resolution changes.
- No new `pick` command behavior in this task.
- No changes to mux entry filtering, ordering, save behavior, or restore behavior.

**Error Handling**

The command keeps the current behavior for empty results and command availability. This task changes only how successful list output is formatted.

**Testing**

Shell tests should cover:

- live `cmux` list output with the simplified four-column header
- saved-state fallback list output with the same four-column header
- absence of the deprecated `Title` column
- absence of `(*)` markers
- absence of list helper text
