# Mux Backlog

**Current state:** `bin/mux` now auto-saves on mux-managed session entry, `mux save` and `mux s` rewrite the snapshot on demand, `mux list` exposes numeric and letter selectors, bare selectors fall back to literal tmux session names when no listed mux tab matches, `mux cleanup` removes orphan tmux sessions from the live `cmux` host after confirmation, remote shells can still use `mux` without `cmux`, and `README.md` documents the current CLI behavior.

## Remaining Work

### Task 1: Research Automatic Persistence on Tab Changes

**Files:**
- Create: `docs/plans/2026-03-23-mux-auto-persist-hooks-spike.md`

**Goal:** decide whether mux should rely on tmux hooks, polling, or a hybrid approach to keep the saved state fresh after tab lifecycle changes that do not go through the `mux` wrapper.

**Questions to answer:**
- Does cmux expose documented event subscriptions or listeners for workspace or surface lifecycle changes?
- If not, which tmux hooks are close enough to cover session and window lifecycle changes?
- Which user actions remain invisible to tmux hooks because they are cmux UI events rather than tmux events?
- Is polling `cmux tree --all --json` acceptable as a fallback, and at what interval?

**Deliverable:**
- Write a short spike doc at `docs/plans/2026-03-23-mux-auto-persist-hooks-spike.md` with the recommendation, caveats, and the next implementation step.

### Task 2: Add `mux close` for Listed Tabs and Named Sessions

**Files:**
- Update: `bin/mux`
- Update: `README.md`

**Goal:** support `mux close 1`, `mux close a`, and `mux close <name>` so the command kills the targeted tmux session without closing the corresponding cmux tab.

**Requirements:**
- Accept the same numeric, letter, and literal-name selectors that `mux attach` and related commands already understand.
- Resolve the selector to the mux-managed tab/session entry before destroying anything.
- Kill the tmux session for the resolved target.
- Do not close the matching cmux tab as part of the command flow.
- Document the command behavior and examples in `README.md`.

### Task 5: Make `mux` Show Help and Add Non-Destructive Command Aliases

**Standalone:** yes
**Depends on:** none

**Files:**
- Update: `bin/mux`
- Update: `README.md`
- Update: `tests/run-tests.sh`

**Goal:** make the CLI fully command-first for help and lookup commands.

**Requirements:**
- Make `mux`, `mux help`, `mux -h`, and `mux --help` show usage.
- Add `mux l` as an alias for `mux list`.
- Add `mux r` as an alias for `mux restore`.
- Update tests for the new aliases and default help behavior.
- Update `README.md` examples and usage text.

### Task 6: Remove Bare `mux <name>` and Make `t`/`tab` the Only Session-Launch Commands

**Standalone:** no
**Depends on:** Task 5

**Files:**
- Update: `bin/mux`
- Update: `README.md`
- Update: `tests/run-tests.sh`

**Goal:** remove implicit bare-name launching and require an explicit launch command.

**Requirements:**
- Remove bare `mux <name>` as a supported way to open or create tmux sessions.
- Support `mux t <name>` and `mux tab <name>` as the only session-launch commands.
- Make `mux t 1` and `mux t a` treat the argument as a literal tmux session name rather than a list selector.
- Update tests for the removed bare-name behavior and the new `t` alias.
- Update `README.md` examples and usage text.

### Task 7: Standardize Session Tab Titles as `mux <name>`

**Standalone:** no
**Depends on:** Task 6

**Files:**
- Update: `bin/mux`
- Update: `README.md`
- Update: `tests/run-tests.sh`

**Goal:** make all session-launch commands use the same visible tab title format.

**Requirements:**
- Make both `mux t <name>` and `mux tab <name>` rename the visible tab to `mux <name>`.
- Ensure persistence and restore still recognize and handle standardized `mux <name>` titles.
- Update tests for the standardized title behavior.
- Update `README.md` examples and restore notes.

### Task 8: Remove the Redundant `Title` Column from `mux list`

**Standalone:** yes
**Depends on:** none

**Files:**
- Update: `bin/mux`
- Update: `README.md`
- Update: `tests/run-tests.sh`

**Goal:** simplify `mux list` output by hiding the tab title column.

**Requirements:**
- Remove the `Title` column from list output.
- Keep the numeric selector, letter selector, workspace, and session columns.
- Update list-format tests.
- Update `README.md` examples if needed.

### Task 9: Add Non-Interactive `mux pick <selector>` and `mux p <selector>`

**Standalone:** yes
**Depends on:** none

**Files:**
- Update: `bin/mux`
- Update: `README.md`
- Update: `tests/run-tests.sh`

**Goal:** add a selector-only command that resolves existing mux list entries without creating new sessions.

**Requirements:**
- Add `mux pick` and `mux p` as selector commands.
- Support `mux pick 1`, `mux pick a`, and similar direct selectors without prompting.
- Keep `mux pick` selector-only: it must resolve existing mux list entries and never create a new tmux session as a fallback.
- Return a clear error when the requested selector does not match a listed mux entry.
- Update tests for direct selector behavior and no-fallback behavior.
- Update `README.md` examples and usage text.

### Task 10: Add Interactive `mux pick` with No Selector

**Standalone:** no
**Depends on:** Task 9

**Files:**
- Update: `bin/mux`
- Update: `README.md`
- Update: `tests/run-tests.sh`

**Goal:** make `mux pick` interactive when no selector is passed.

**Requirements:**
- Support `mux pick` and `mux p` with no selector as an interactive picker that shows the list and waits for user input in interactive terminals.
- Reuse the same selector resolution rules as `mux pick <selector>`.
- Avoid hanging in non-interactive contexts such as pipes or scripts.
- Update tests for interactive and non-interactive behavior.
- Update `README.md` examples and usage text.

## Research Notes

- tmux documents server, session, and window hooks such as `window-renamed`, plus control-mode notifications including `%window-add`, `%window-close`, and `%window-renamed`: https://man7.org/linux/man-pages/man1/tmux.1.html
- tmux control mode event examples: https://github.com/tmux/tmux/wiki/Control-Mode/fd5e33023fe7c16cb573b954d05c70e16d225a9a
- cmux documents a CLI and Unix socket request API, but the reviewed official pages do not document an event subscription or listener interface: https://www.cmux.dev/docs/api
- cmux current restore behavior and automation positioning: https://www.cmux.dev/docs/getting-started
