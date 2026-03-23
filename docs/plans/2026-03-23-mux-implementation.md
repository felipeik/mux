# Mux Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone Bash CLI named `mux` that snapshots all cmux workspaces and best-effort restores only terminals created as `mux tab <name>`.

**Architecture:** The CLI is a single Bash entrypoint supported by a small shell test harness. `persist` reads `cmux` JSON and rewrites one state file; `restore` matches current workspaces by title and respawns only recognized tmux-backed terminal surfaces with `mux tab <name>`.

**Tech Stack:** Bash, jq, cmux CLI, tmux, shell-based test scripts

---

### Task 1: Project Skeleton

**Files:**
- Create: `mux/bin/mux`
- Create: `mux/README.md`
- Create: `mux/tests/run-tests.sh`
- Create: `mux/tests/helpers/assert.sh`

**Step 1: Write the failing test**

Create a test runner that expects `mux/bin/mux` to exist and respond to `help`.

**Step 2: Run test to verify it fails**

Run: `bash mux/tests/run-tests.sh`
Expected: FAIL because `mux/bin/mux` does not exist yet.

**Step 3: Write minimal implementation**

Create an executable Bash script with command dispatch for `tab`, `persist`, and `restore`.

**Step 4: Run test to verify it passes**

Run: `bash mux/tests/run-tests.sh`
Expected: PASS for the help/dispatch bootstrap test.

**Step 5: Commit**

```bash
git add mux/bin/mux mux/README.md mux/tests/run-tests.sh mux/tests/helpers/assert.sh
git commit -m "feat: scaffold mux cli"
```

### Task 2: Implement `mux tab`

**Files:**
- Modify: `mux/bin/mux`
- Modify: `mux/tests/run-tests.sh`

**Step 1: Write the failing test**

Add a test that stubs `tmux` and expects `mux tab claude-123` to invoke `tmux new-session -A -s claude-123`.

**Step 2: Run test to verify it fails**

Run: `bash mux/tests/run-tests.sh`
Expected: FAIL because `tab` does not call tmux correctly.

**Step 3: Write minimal implementation**

Implement `tab` with input validation and `exec tmux new-session -A -s "$name"`.

**Step 4: Run test to verify it passes**

Run: `bash mux/tests/run-tests.sh`
Expected: PASS for `tab`.

**Step 5: Commit**

```bash
git add mux/bin/mux mux/tests/run-tests.sh
git commit -m "feat: add mux tab"
```

### Task 3: Implement `persist`

**Files:**
- Modify: `mux/bin/mux`
- Modify: `mux/tests/run-tests.sh`

**Step 1: Write the failing test**

Add tests that stub `cmux tree --all --json`, then verify:

- the state file is fully rewritten
- only terminal surfaces titled `mux tab <name>` are saved
- workspaces are keyed by title

**Step 2: Run test to verify it fails**

Run: `bash mux/tests/run-tests.sh`
Expected: FAIL because `persist` is missing or writes the wrong JSON.

**Step 3: Write minimal implementation**

Implement `persist` using `jq` to extract recognized surfaces and write a single JSON state file.

**Step 4: Run test to verify it passes**

Run: `bash mux/tests/run-tests.sh`
Expected: PASS for `persist`.

**Step 5: Commit**

```bash
git add mux/bin/mux mux/tests/run-tests.sh
git commit -m "feat: add mux persist"
```

### Task 4: Implement `restore`

**Files:**
- Modify: `mux/bin/mux`
- Modify: `mux/tests/run-tests.sh`

**Step 1: Write the failing test**

Add tests that stub current cmux workspaces and validate:

- matching happens by workspace title
- missing workspaces are skipped
- existing terminal surfaces are matched by saved pane position
- `cmux respawn-pane` is used to run `mux tab <name>`
- failures on one restore target do not stop the rest

**Step 2: Run test to verify it fails**

Run: `bash mux/tests/run-tests.sh`
Expected: FAIL because `restore` is incomplete.

**Step 3: Write minimal implementation**

Implement best-effort restore with per-entry error handling by respawning existing terminal surfaces.

**Step 4: Run test to verify it passes**

Run: `bash mux/tests/run-tests.sh`
Expected: PASS for `restore`.

**Step 5: Commit**

```bash
git add mux/bin/mux mux/tests/run-tests.sh
git commit -m "feat: add mux restore"
```

### Task 5: Document Usage

**Files:**
- Modify: `mux/README.md`

**Step 1: Write the failing test**

Add a lightweight documentation check in the test runner that expects README usage examples for `tab`, `persist`, and `restore`.

**Step 2: Run test to verify it fails**

Run: `bash mux/tests/run-tests.sh`
Expected: FAIL because README is incomplete.

**Step 3: Write minimal implementation**

Document installation, state file location, and the rule that only `mux tab <name>` terminals are restored.

**Step 4: Run test to verify it passes**

Run: `bash mux/tests/run-tests.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add mux/README.md
git commit -m "docs: add mux usage"
```
