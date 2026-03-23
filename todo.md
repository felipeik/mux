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

## Research Notes

- tmux documents server, session, and window hooks such as `window-renamed`, plus control-mode notifications including `%window-add`, `%window-close`, and `%window-renamed`: https://man7.org/linux/man-pages/man1/tmux.1.html
- tmux control mode event examples: https://github.com/tmux/tmux/wiki/Control-Mode/fd5e33023fe7c16cb573b954d05c70e16d225a9a
- cmux documents a CLI and Unix socket request API, but the reviewed official pages do not document an event subscription or listener interface: https://www.cmux.dev/docs/api
- cmux current restore behavior and automation positioning: https://www.cmux.dev/docs/getting-started
