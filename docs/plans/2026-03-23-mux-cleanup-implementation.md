# Mux Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `mux cleanup` as a `cmux`-required command that refreshes mux state through the save path, lists orphan tmux sessions not present in the live `cmux` tree, and deletes them only after confirmation or `--auto-approve`.

**Architecture:** `bin/mux` remains a single Bash entrypoint with shell-based tests. Cleanup will share the existing live mux entry extraction logic, add a small tmux-session difference helper, require `cmux`, and keep the destructive path gated behind exact confirmation unless `--auto-approve` is passed.

**Tech Stack:** Bash, jq, cmux CLI, tmux CLI, shell-based test scripts

---

### Task 1: Add Failing Cleanup Tests

**Files:**
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add shell tests that verify:

- `mux cleanup` calls the save path before comparing sessions when `cmux` is available
- orphan tmux sessions are listed before deletion
- any answer other than exact `yes` aborts without killing sessions
- exact `yes` kills every listed orphan session
- `--auto-approve` skips the prompt and still kills every orphan session
- `nothing to cleanup` is printed when there are no orphan sessions
- cleanup fails when `cmux` is unavailable

Use stubbed `cmux`, `jq`, and `tmux` binaries so the test can assert call order, prompts, and `tmux kill-session -t` targets.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL because `mux cleanup` does not exist yet.

**Step 3: Write minimal implementation**

Do not implement yet. Keep the failure in place for the red step.

**Step 4: Run test to verify it passes**

Skip until Task 2.

**Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: cover mux cleanup"
```

### Task 2: Implement `mux cleanup`

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Reuse the red tests from Task 1.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL on missing cleanup command handling.

**Step 3: Write minimal implementation**

Update `bin/mux` so:

- usage text includes `cleanup [--auto-approve]`
- command dispatch recognizes `cleanup`
- cleanup requires `cmux`, `jq`, and `tmux`
- cleanup triggers the internal save path before reading the live `cmux tree --all --json`
- cleanup derives the tracked tmux session set from live mux entries only
- cleanup lists orphan tmux sessions from `tmux list-sessions -F '#{session_name}'`
- cleanup prompts for exact `yes` unless `--auto-approve` is passed
- cleanup kills each orphan with `tmux kill-session -t <name>`
- cleanup prints `nothing to cleanup` and exits `0` when no orphan sessions are found

Keep the implementation DRY by reusing the existing live entry parsing and tmux session listing helpers.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS for the new cleanup tests and the existing suite.

**Step 5: Commit**

```bash
git add bin/mux tests/run-tests.sh
git commit -m "feat: add mux cleanup"
```

### Task 3: Refresh Documentation

**Files:**
- Modify: `README.md`

**Step 1: Write the failing test**

Inspect the current README usage text and identify the places that need cleanup command documentation.

**Step 2: Run test to verify it fails**

No automated README-specific test exists, so verification here is manual file review plus the full shell suite.

**Step 3: Write minimal implementation**

Document:

- `mux cleanup`
- `mux cleanup --auto-approve`
- the exact confirmation requirement
- that cleanup requires a live `cmux` host
- that cleanup removes tmux sessions not represented in the current live mux tree

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS unchanged after documentation updates.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: document mux cleanup"
```

### Task 4: Update Backlog After Shipping Cleanup

**Files:**
- Modify: `todo.md`

**Step 1: Write the failing test**

Review `todo.md` and identify the shipped cleanup task that should be removed or marked complete.

**Step 2: Run test to verify it fails**

No automated backlog test exists, so verification here is manual file review.

**Step 3: Write minimal implementation**

Remove the completed `mux cleanup` item from the backlog while preserving the remaining open tasks.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS unchanged after backlog cleanup.

**Step 5: Commit**

```bash
git add todo.md
git commit -m "docs: update mux backlog after cleanup"
```
