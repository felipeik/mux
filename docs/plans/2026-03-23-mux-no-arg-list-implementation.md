# Mux No-Arg List Alias Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make bare `mux` behave exactly like `mux list` while keeping `-h`, `--help`, and `help` mapped to usage output.

**Architecture:** Keep the change in the existing Bash dispatcher. Add one shell test for the no-arg alias, extend help coverage for both flag forms, then switch the empty-argument case in `main` from `usage` to `cmd_list`.

**Tech Stack:** Bash, shell test harness, jq, tmux/cmux stubs

---

### Task 1: Add Failing CLI Dispatch Tests

**Files:**
- Modify: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add a shell test that stubs `cmux` and `tmux`, runs `mux` with no args, and expects the same list helper text that `mux list` prints. Extend help coverage so `mux -h` and `mux --help` still print usage output.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL because bare `mux` still prints usage instead of list output.

**Step 3: Write minimal implementation**

Do not change production code yet.

**Step 4: Run test to verify it passes**

Skip until Task 2.

**Step 5: Commit**

```bash
git add tests/run-tests.sh
git commit -m "test: cover mux no-arg alias"
```

### Task 2: Implement No-Arg List Alias

**Files:**
- Modify: `bin/mux`

**Step 1: Write the failing test**

Reuse the failing dispatch test from Task 1.

**Step 2: Run test to verify it fails**

Run: `bash tests/run-tests.sh`
Expected: FAIL on the bare `mux` dispatch assertion.

**Step 3: Write minimal implementation**

Update `main` so:

- `""` dispatches to `cmd_list`
- `-h`, `--help`, and `help` dispatch to `usage`
- all other cases stay unchanged

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add bin/mux tests/run-tests.sh
git commit -m "feat: alias bare mux to list"
```

### Task 3: Refresh Documentation

**Files:**
- Modify: `README.md`

**Step 1: Write the failing test**

Inspect the command list and usage text in `README.md` for missing no-arg guidance.

**Step 2: Run test to verify it fails**

No dedicated README behavior test exists beyond string presence, so manual review is the red step here.

**Step 3: Write minimal implementation**

Document bare `mux` as an alias for `mux list` and keep help flag behavior clear.

**Step 4: Run test to verify it passes**

Run: `bash tests/run-tests.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: document bare mux list alias"
```
