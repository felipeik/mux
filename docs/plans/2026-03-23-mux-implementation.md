# Mux Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `mux <name>` as the preferred alias for `mux tab <name>` while preserving persist/restore compatibility for both title formats.

**Architecture:** The CLI stays as a single Bash entrypoint with shell-based tests. Command parsing will treat an unknown first token as a session name, visible cmux tab titles will use `mux <name>` for the new shortcut, and persist/restore detection will recognize both `mux <name>` and `mux tab <name>` so old and new sessions restore to the same tmux target.

**Tech Stack:** Bash, jq, cmux CLI, tmux, shell-based test scripts

---

### Task 1: Add Failing Alias Tests

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add a shell test that stubs `tmux` and `cmux`, then expects `mux claude-123` to rename the visible tab to `mux claude-123` and run `tmux new-session -A -s claude-123`.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL because bare session names are not recognized yet.

**Step 3: Write minimal implementation**

Do not implement yet. Keep the code unchanged so the red step stays valid.

**Step 4: Run test to verify it passes**

Skip until implementation is added in Task 3.

**Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: cover bare mux session alias"
```

### Task 2: Add Failing Persist and Restore Compatibility Tests

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Extend the shell tests so `persist` saves both `mux tab backend` and `mux backend`, and `restore` respawns both formats using the session name parsed from each title.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL because the current jq patterns only recognize `mux tab <name>`.

**Step 3: Write minimal implementation**

Do not implement yet. Keep the code unchanged so the red step stays valid.

**Step 4: Run test to verify it passes**

Skip until implementation is added in Task 3.

**Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: cover mux title compatibility"
```

### Task 3: Implement Bare Session Alias and Shared Title Parsing

**Files:**
- Modify: `bin/mux`
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Reuse the failing tests from Tasks 1 and 2.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL on bare-session dispatch and mixed title parsing.

**Step 3: Write minimal implementation**

Update `bin/mux` so:

- help shows `mux <name>` as preferred usage
- a bare first argument is treated as `cmd_tab "$1"`
- the visible cmux title becomes `mux <name>` for bare-session launches
- title parsing and restore command generation accept both `mux <name>` and `mux tab <name>`

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS for the new alias tests and the existing suite.

**Step 5: Commit**

```bash
git add bin/mux tests/run-tests.sh
git commit -m "feat: add bare mux session alias"
```

### Task 4: Refresh Documentation

**Files:**
- Modify: `README.md`

**Step 1: Write the failing test**

Inspect the current README usage text and identify the stale command examples that still imply `mux tab <name>` is the only supported session entrypoint.

**Step 2: Run test to verify it fails**

No automated README test exists, so verification here is manual file review.

**Step 3: Write minimal implementation**

Document `mux <name>` as the preferred usage, note that `mux tab <name>` remains supported, and explain that persist/restore recognize both title formats.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS unchanged after documentation updates.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: prefer bare mux session usage"
```
