# mux join Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** add selector-only `mux join` and `mux j` commands, including interactive selector prompting for no-arg calls, without changing existing bare `mux` behavior.

**Architecture:** keep the existing mux list entry discovery and selector resolution logic, then layer a dedicated `join` command path on top. Add one interactive helper that reuses the list output and selector resolver, while keeping the existing bare argument fallback behavior unchanged for non-join commands.

**Tech Stack:** Bash, tmux, cmux, jq, shell test harness in `tests/run-tests.sh`

---

### Task 1: Add failing tests for selector-only join commands

**Files:**
- Modify: `tests/run-tests.sh`
- Modify: `bin/mux`
- Test: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add tests that express:

```bash
test_mux_join_numeric_selector_attaches_by_list_index
test_mux_join_alias_letter_selector_attaches_by_list_key
test_mux_join_unknown_selector_does_not_fall_back_to_literal_session
```

Each test should stub `cmux`, `jq`, and `tmux` exactly like the existing selector tests, then assert that `join`/`j` either attaches to the resolved session or fails without launching a literal fallback session.

**Step 2: Run test to verify it fails**

Run: `./tests/run-tests.sh`
Expected: FAIL because `join` and `j` are not recognized yet.

**Step 3: Write minimal implementation**

Add a dedicated join command path in `bin/mux` that:

```bash
cmd_join_selector() {
  local selector="$1" entry session

  if ! entry="$(find_entry_by_selector "$selector")"; then
    echo "unknown mux selector: $selector" >&2
    exit 1
  fi

  session="$(printf '%s\n' "$entry" | jq -r '.session')"
  exec tmux new-session -A -s "$session"
}
```

Route both `join` and `j` to that path when one selector argument is provided.

**Step 4: Run test to verify it passes**

Run: `./tests/run-tests.sh`
Expected: the new join tests pass and the existing selector tests remain green.

**Step 5: Commit**

```bash
git add tests/run-tests.sh bin/mux
git commit -m "feat: add selector-only mux join command"
```

### Task 2: Add failing tests for interactive and non-interactive no-arg join

**Files:**
- Modify: `tests/run-tests.sh`
- Modify: `bin/mux`
- Test: `tests/run-tests.sh`

**Step 1: Write the failing test**

Add tests covering:

```bash
test_mux_join_without_selector_reads_prompt_in_interactive_mode
test_mux_join_without_selector_prints_list_and_errors_in_non_interactive_mode
```

The interactive test should run the command under a pseudo-terminal, feed `1` or `a`, and assert that the list is shown before `tmux new-session -A -s <session>`. The non-interactive test should pipe or redirect stdin so the command is not interactive, then assert that the list is printed and that no tmux attach/create call occurs.

**Step 2: Run test to verify it fails**

Run: `./tests/run-tests.sh`
Expected: FAIL because `join` currently requires an explicit selector or lacks the prompt behavior.

**Step 3: Write minimal implementation**

Add helpers that:

```bash
is_interactive_terminal() {
  [ -t 0 ] && [ -t 1 ]
}

cmd_join() {
  local selector="${1:-}"

  if [ -n "$selector" ]; then
    cmd_join_selector "$selector"
  fi

  cmd_list
  if ! is_interactive_terminal; then
    echo "selector required in non-interactive mode" >&2
    exit 1
  fi

  printf 'selector: ' >&2
  IFS= read -r selector || true
  cmd_join_selector "$selector"
}
```

If the current `cmd_list` format writes only to stdout, keep it that way so the list is visible in both interactive and scripted use.

**Step 4: Run test to verify it passes**

Run: `./tests/run-tests.sh`
Expected: both no-arg join tests pass without regressing the command table or selector behavior.

**Step 5: Commit**

```bash
git add tests/run-tests.sh bin/mux
git commit -m "feat: add interactive mux join flow"
```

### Task 3: Update docs and backlog, then verify

**Files:**
- Modify: `README.md`
- Modify: `todo.md`
- Test: `tests/run-tests.sh`

**Step 1: Write the failing doc expectation**

Update the command list and selector rules in `README.md` so they describe:

```text
- mux join <selector> and mux j <selector>
- no fallback to literal session names
- interactive join with no selector
- non-interactive no-arg join prints the list and exits with an error
```

Update `todo.md` so the old `pick` tasks are replaced or marked complete in terms of `join`.

**Step 2: Run verification**

Run: `./tests/run-tests.sh`
Expected: PASS

**Step 3: Commit**

```bash
git add README.md todo.md tests/run-tests.sh bin/mux
git commit -m "docs: document mux join command"
```
