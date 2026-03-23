# mux Explicit Launch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove bare-name launching, add `mux t`, and standardize persisted mux titles on `mux <name>`.

**Architecture:** Keep selector-based joins on bare arguments, route all explicit session creation through one shared launch helper, and narrow persistence/restore title parsing to the canonical `mux <name>` form. This keeps list, save, and restore consistent while avoiding selector fallback side effects.

**Tech Stack:** Bash, tmux, cmux, jq, shell test runner

---

### Task 1: Update Tests First

**Files:**
- Modify: `tests/run-tests.sh`

**Step 1: Write failing tests**

- Replace bare-name launch expectations with explicit `mux t <name>` and canonical `mux <name>` title assertions.
- Add or adjust tests so unmatched bare arguments fail instead of launching tmux sessions.
- Update save/restore fixtures to use only canonical `mux <name>` titles.
- Update README assertions to require `mux t <name>` and reject `mux <name>` launch docs.

**Step 2: Run tests to verify failure**

Run: `./tests/run-tests.sh`
Expected: FAIL in the launch, restore, and README coverage that still reflects bare launches or `mux tab <name>` titles.

### Task 2: Implement Explicit Launching

**Files:**
- Modify: `bin/mux`

**Step 1: Write minimal implementation**

- Add `t` as a launch command alias.
- Make `tab` and `t` share one literal-session launch path.
- Make bare arguments resolve selectors only and error when no mux entry matches.
- Standardize rename, save, live entry parsing, and restore command generation on `mux <name>`.

**Step 2: Run tests to verify green**

Run: `./tests/run-tests.sh`
Expected: PASS

### Task 3: Update Docs and Backlog

**Files:**
- Modify: `README.md`
- Modify: `todo.md`

**Step 1: Update docs**

- Document `mux t <name>` and `mux tab <name>` as the launch commands.
- Document that bare selectors join existing entries and no longer fall back to literal session creation.
- Document canonical restore behavior around `mux <name>` titles only.

**Step 2: Update backlog**

- Mark Tasks 6 and 7 as completed by removing them from the remaining backlog and folding the new state into the summary text.

**Step 3: Re-run verification**

Run: `./tests/run-tests.sh`
Expected: PASS
