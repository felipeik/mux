# Mux Backlog

**Current state:** `bin/mux` now auto-persists on mux-managed session entry, `mux list` exposes numeric and letter selectors, bare selectors fall back to literal tmux session names when no listed mux tab matches, remote shells can still use `mux` without `cmux`, and `README.md` documents the current CLI behavior.

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

### Task 3: Add `mux cleanup` for Non-Snapshotted tmux Sessions

**Files:**
- Update: `bin/mux`
- Update: `README.md`

**Goal:** support `mux cleanup` as a bulk cleanup command that finds tmux sessions not represented in the current mux snapshot, shows the sessions that would be removed, asks for an explicit `yes` confirmation, and then kills all listed tmux sessions.

**Requirements:**
- Read the current mux snapshot and derive the set of tmux session names tracked by mux-managed tabs.
- List tmux sessions that exist in tmux but are not present in the mux snapshot.
- Show the unmatched session names before any destructive action happens.
- Require an explicit `yes` confirmation before proceeding with deletion.
- Kill every listed unmatched tmux session after confirmation.
- Abort without changes for any answer other than `yes`.
- Document the command behavior, confirmation requirement, and examples in `README.md`.

## Research Notes

- tmux documents server, session, and window hooks such as `window-renamed`, plus control-mode notifications including `%window-add`, `%window-close`, and `%window-renamed`: https://man7.org/linux/man-pages/man1/tmux.1.html
- tmux control mode event examples: https://github.com/tmux/tmux/wiki/Control-Mode/fd5e33023fe7c16cb573b954d05c70e16d225a9a
- cmux documents a CLI and Unix socket request API, but the reviewed official pages do not document an event subscription or listener interface: https://www.cmux.dev/docs/api
- cmux current restore behavior and automation positioning: https://www.cmux.dev/docs/getting-started
