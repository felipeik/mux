# Unmanaged Tmux Sessions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend `mux list` and `mux join` so live tmux sessions that are missing from the mux snapshot are still shown and selectable.

**Architecture:** Keep the current mux-managed discovery path intact, then derive a second stream of unmanaged tmux-only entries by subtracting tracked session names from `tmux list-sessions`. Concatenate those two streams into one selector list so `list` rendering and `join` resolution continue to share the same source.

**Tech Stack:** Bash, `jq`, tmux, shell test harness in `tests/run-tests.sh`

---

### Task 1: Capture the regression in tests

**Files:**
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add one test that expects `mux list` to append unmanaged tmux sessions after mux-managed rows and another that expects `mux join` to attach to one of those appended rows.

**Step 2: Run test to verify it fails**

Run: `tests/run-tests.sh`
Expected: the new assertions fail because unmanaged tmux sessions are not currently listed or selectable.

**Step 3: Write minimal implementation**

Do not implement here.

**Step 4: Run test to verify it still fails correctly**

Run: `tests/run-tests.sh`
Expected: the same targeted failures remain, confirming the regression is real.

### Task 2: Combine mux-managed and unmanaged tmux entries

**Files:**
- Modify: `bin/mux`

**Step 1: Write the failing test**

Covered by Task 1.

**Step 2: Run test to verify it fails**

Run: `tests/run-tests.sh`
Expected: the new list and join tests fail before code changes.

**Step 3: Write minimal implementation**

- Introduce a helper that emits the combined selector source.
- Preserve current mux-managed entry ordering.
- Append unmanaged tmux sessions as synthetic entries with workspace `-` and title `mux <session>`.
- Update selector resolution and list rendering to use the combined entries.
- Keep cleanup logic on mux-managed tracking only.

**Step 4: Run test to verify it passes**

Run: `tests/run-tests.sh`
Expected: the new regressions pass along with the existing shell tests.

### Task 3: Update docs and backlog state

**Files:**
- Modify: `README.md`
- Modify: `todo.md`

**Step 1: Write the failing test**

Existing README coverage in `tests/run-tests.sh` should continue to validate the usage text.

**Step 2: Run test to verify doc expectations**

Run: `tests/run-tests.sh`
Expected: README assertions still pass after wording updates.

**Step 3: Write minimal implementation**

- Document that `mux list` includes appended unmanaged tmux sessions.
- Document that `mux join` selectors may target those appended rows.
- Refresh `todo.md` current state to reflect the new behavior.

**Step 4: Run test to verify it passes**

Run: `tests/run-tests.sh`
Expected: docs remain consistent with the CLI.
