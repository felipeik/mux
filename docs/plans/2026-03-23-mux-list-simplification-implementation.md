# Mux List Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify `mux list` so it prints only selector, workspace, and tmux session data, with no title column, conflict markers, or helper text.

**Architecture:** `bin/mux` remains a single Bash CLI with shell-script tests. The implementation will narrow the list renderer to four columns, remove the selector-decoration helper that produced `(*)`, and keep both the live `cmux` and saved-state fallback paths on the same output format.

**Tech Stack:** Bash, jq, cmux CLI, tmux CLI, shell-based test scripts

---

### Task 1: Add Failing List Output Tests

**Files:**
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Update the existing list-format assertions so they expect:

- a four-column header without `Title`
- plain selector values without `(*)`
- no top helper line
- no bottom helper line

Cover both the live `cmux` list path and the saved-state fallback path.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL because the current implementation still prints the `Title` column, `(*)`, and helper text.

**Step 3: Write minimal implementation**

Do not implement yet. Keep the failures in place for the red step.

**Step 4: Run test to verify it passes**

Skip until Task 2.

**Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: cover simplified mux list output"
```

### Task 2: Simplify `mux list` Rendering

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Reuse the red assertions from Task 1.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL on the outdated list header and helper text.

**Step 3: Write minimal implementation**

Update `bin/mux` so:

- `cmd_list` renders only index, key, workspace, and session
- the `Title` column is removed from the width calculations and row output
- deprecated selector-conflict formatting is removed
- `mux list` prints no helper text before or after the table

Keep the existing mux entry filtering, ordering, and fallback behavior unchanged.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS for the updated list tests and the rest of the suite.

**Step 5: Commit**

```bash
git add bin/mux tests/run-tests.sh
git commit -m "feat: simplify mux list output"
```

### Task 3: Refresh Documentation

**Files:**
- Modify: `README.md`

**Step 1: Write the failing test**

Inspect the current README command and selector descriptions for references to the title column, conflict markers, or list helper guidance.

**Step 2: Run test to verify it fails**

No automated README-specific test exists, so verification is manual review plus the full shell suite.

**Step 3: Write minimal implementation**

Update `README.md` so it describes `mux list` as a plain table of selectors, workspaces, and sessions without conflict markers or list helper text.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS unchanged after documentation updates.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: refresh mux list output docs"
```

### Task 4: Update Backlog After Shipping Task 8

**Files:**
- Modify: `todo.md`

**Step 1: Write the failing test**

Review `todo.md` and identify the completed Task 8 entry to remove from the remaining backlog.

**Step 2: Run test to verify it fails**

No automated backlog test exists, so verification is manual review.

**Step 3: Write minimal implementation**

Remove the completed Task 8 item while preserving the remaining open tasks.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS unchanged after backlog cleanup.

**Step 5: Commit**

```bash
git add todo.md
git commit -m "docs: update mux backlog after list simplification"
```
