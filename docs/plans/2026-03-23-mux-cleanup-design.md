# Mux Cleanup Design

**Goal**

Add a destructive maintenance command, `mux cleanup`, that removes tmux sessions which are not represented by the current live `cmux` mux-managed tab set.

**Scope**

- Add `mux cleanup` with no short alias.
- Support `mux cleanup --auto-approve` as the only non-interactive confirmation bypass.
- Require `cmux` to be available for cleanup.
- Refresh mux state through the save path before computing orphan tmux sessions.
- Use the live `cmux tree --all --json` view as the source of truth for tracked mux sessions.
- Print `nothing to cleanup` and exit successfully when no orphan tmux sessions exist.
- Update the README to document the command, confirmation flow, and `cmux` requirement.

**Architecture**

`mux cleanup` will stay inside the existing single-file Bash CLI and reuse the same title-parsing rules already used by `mux list` and state saving.

When cleanup runs, it will first refresh state through the internal save helper, then read the live `cmux` tree and extract the mux-managed tmux session names. It will separately read `tmux list-sessions -F '#{session_name}'`, compute the set difference, present the orphan session names, and kill each orphan with `tmux kill-session -t <name>` after confirmation.

**Command Model**

- `mux cleanup`
  Lists orphan tmux sessions, prompts for exact `yes`, and deletes them only after confirmation.
- `mux cleanup --auto-approve`
  Skips the confirmation prompt and immediately deletes the listed orphan tmux sessions.

There is no `mux c` alias because cleanup is destructive.

**Source of Truth**

Cleanup is intentionally host-local and `cmux`-dependent. The command does not fall back to the saved snapshot when `cmux` is unavailable.

The tracked mux session set comes from the current live `cmux tree --all --json` output after the save path is triggered. This keeps cleanup aligned with what is currently visible in `cmux`, rather than a possibly stale snapshot.

**Output and Confirmation**

- If no orphan tmux sessions are found, print `nothing to cleanup`.
- If orphan sessions are found, print a short header plus one session name per line.
- Without `--auto-approve`, prompt `Type yes to delete these sessions:`.
- Only exact `yes` proceeds.
- Any other answer exits without deleting sessions.

**Error Handling**

- Missing `cmux` exits with a clear error because cleanup requires an active `cmux` host view.
- Missing `jq` exits with a clear error because cleanup needs the live JSON tree.
- Missing `tmux` exits with a clear error because cleanup must inspect and kill tmux sessions.
- If the save step fails, cleanup exits and does not delete anything.
- If one `tmux kill-session` call fails, the command should stop and surface the failure instead of claiming full cleanup succeeded.

**Testing**

Shell tests should cover:

- `mux cleanup` refreshing the snapshot through the save path before orphan detection.
- `mux cleanup` listing orphan tmux sessions and refusing deletion when the answer is not exact `yes`.
- `mux cleanup` deleting all orphan tmux sessions after exact `yes`.
- `mux cleanup --auto-approve` deleting without reading confirmation input.
- `mux cleanup` printing `nothing to cleanup` when every tmux session is tracked.
- `mux cleanup` failing when `cmux` is unavailable.
