# Mux Next Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add automatic persistence on mux session entry, numeric tab selection via `mux list` and `mux <index>`, and a research-backed path for automatic persistence on tab lifecycle changes.

**Architecture:** Keep `bin/mux` as the single Bash entrypoint and extend the shell test harness first. Opening a mux session should become a small workflow: validate the identifier, rename the cmux tab, best-effort persist the current cmux tree, then enter the tmux session. Numeric arguments will be reserved for list selection only, and `mux list` will derive its output from the live `cmux tree --all --json` view rather than the saved state file so the numbering reflects the current UI.

**Tech Stack:** Bash, jq, cmux CLI/socket API, tmux CLI/hooks, shell-based test scripts

---

### Task 1: Add Failing Tests for Auto-Persist and Integer Validation

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add shell tests that verify:

- `mux backend` calls the persist workflow before entering tmux
- `mux tab backend` calls the persist workflow before entering tmux
- `mux 1` does not create or attach to a session literally named `1`
- exact integer names are rejected for `mux tab 1` and `mux 1`
- non-integer names such as `api-1` remain valid

Use stubbed `cmux`, `jq`, and `tmux` binaries in `tests/run-tests.sh` so the test can assert call order and exact arguments.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL because the current CLI enters tmux directly and still allows exact integer session names.

**Step 3: Write minimal implementation**

Do not implement yet. Keep the failure in place for the red step.

**Step 4: Run test to verify it passes**

Skip until Task 2.

**Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: cover mux auto-persist and integer validation"
```

### Task 2: Implement Launch Workflow and Exact-Integer Rejection

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Reuse the red tests from Task 1.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL on missing persist call and missing integer-name validation.

**Step 3: Write minimal implementation**

Update `bin/mux` so:

- a shared validator rejects names matching `^[0-9]+$`
- `mux <name>` and `mux tab <name>` both use one shared open-session helper
- the helper renames the cmux tab first
- the helper then calls the same internal persist path before entering tmux
- if persist fails, print a warning to stderr and still continue into tmux

Implementation note:

- Do not `exec` until after the persist attempt, otherwise the process cannot continue past `tmux new-session -A -s ...`
- Persist should snapshot the already-renamed cmux tab title so the active tab is represented in the saved state

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS for the new launch and validation tests.

**Step 5: Commit**

```bash
git add bin/mux tests/run-tests.sh
git commit -m "feat: auto-persist when opening mux sessions"
```

### Task 3: Add Failing Tests for `mux list` and Numeric Selection

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add shell tests that stub `cmux tree --all --json` and verify:

- `mux list` prints only recognized mux tabs
- each list row starts with a 1-based integer index
- the listing order is stable and deterministic
- `mux 1` resolves to the session name from row 1
- invalid indexes such as `mux 999` fail with a clear error
- non-mux terminals like `lazygit` are excluded from the list

Recommended deterministic ordering:

- workspace title ascending
- pane index ascending
- surface index within pane ascending

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL because `mux list` and index resolution do not exist yet.

**Step 3: Write minimal implementation**

Do not implement yet. Keep the failure in place for the red step.

**Step 4: Run test to verify it passes**

Skip until Task 4.

**Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: cover mux list and numeric session selection"
```

### Task 4: Implement `mux list` and `mux <index>`

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`
- Modify: `README.md`

**Step 1: Write the failing test**

Reuse the red tests from Task 3.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL on missing list command and missing numeric index dispatch.

**Step 3: Write minimal implementation**

Update `bin/mux` so:

- `list` becomes an explicit command in help output and dispatch
- a shared live-query helper extracts recognized mux tabs from `cmux tree --all --json`
- `mux list` prints one row per mux tab with an index on the left
- exact integers in the first positional argument dispatch to a new index-selection command
- index selection resolves the target session from the live list and then enters the same shared open-session helper used by `mux <name>`

Suggested output format:

```text
1  Alpha   mux backend   backend
2  Beta    mux api-1     api-1
```

Keep the implementation DRY by reusing one title parser and one session-entry helper for:

- `mux <name>`
- `mux tab <name>`
- `mux <index>`

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS for list output, numeric dispatch, and existing commands.

**Step 5: Commit**

```bash
git add bin/mux tests/run-tests.sh README.md
git commit -m "feat: add mux list and numeric selection"
```

### Task 5: Research Automatic Persistence on Tab Changes

**Files:**
- Create: `docs/plans/2026-03-23-mux-auto-persist-hooks-spike.md`

**Step 1: Write the research checklist**

Create a short spike doc that answers:

- Does cmux expose documented event subscriptions or listeners for workspace/surface lifecycle changes?
- If not, which tmux hooks are close enough to cover session lifecycle changes?
- Which user actions remain invisible to tmux hooks because they are cmux UI events rather than tmux events?
- Is polling `cmux tree --all --json` acceptable as a fallback, and at what interval?

**Step 2: Run the research**

Use official docs first. Verify at minimum:

- tmux hooks and control-mode events for window/session lifecycle
- cmux API/socket docs for any documented subscription or notification stream

Expected result:

- tmux supports hooks/control-mode events
- cmux official docs currently document commands and a socket API, but no event subscription/listener mechanism was found in the reviewed pages

**Step 3: Write the decision record**

Document one of these conclusions:

- preferred: use tmux hooks for tmux lifecycle plus wrapper-triggered persist for mux-managed entrypoints, then reevaluate whether polling is needed for cmux-only UI changes
- fallback: add a lightweight polling reconciler if hook coverage is insufficient

**Step 4: Verify the spike doc is complete**

Run: `sed -n '1,240p' docs/plans/2026-03-23-mux-auto-persist-hooks-spike.md`
Expected: the doc clearly states the recommendation, caveats, and next implementation step.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-23-mux-auto-persist-hooks-spike.md
git commit -m "docs: add mux auto-persist hooks spike"
```

### Task 6: Refresh Documentation and End-to-End Verification

**Files:**
- Modify: `README.md`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Extend the README usage assertions so the docs mention:

- automatic persist on `mux <name>` and `mux tab <name>`
- `mux list`
- the reservation of exact integers for list selection

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL until the README is updated.

**Step 3: Write minimal implementation**

Update the README so the command set and routing rules are explicit:

- `mux <name>` attaches by session name
- `mux <index>` attaches by list position
- exact integer names are invalid as direct session names
- automatic persistence happens on mux-managed session entry

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS for the full shell suite.

**Step 5: Commit**

```bash
git add README.md tests/run-tests.sh
git commit -m "docs: document mux list and auto-persist behavior"
```

## Research Notes

- tmux documents server/session/window hooks such as `window-renamed` and control-mode notifications including `%window-add`, `%window-close`, and `%window-renamed`: https://man7.org/linux/man-pages/man1/tmux.1.html
- tmux control mode event examples: https://github.com/tmux/tmux/wiki/Control-Mode/fd5e33023fe7c16cb573b954d05c70e16d225a9a
- cmux documents a CLI and Unix socket request API, but the reviewed official pages do not document an event subscription/listener interface: https://www.cmux.dev/docs/api
- cmux current restore behavior and automation positioning: https://www.cmux.dev/docs/getting-started
