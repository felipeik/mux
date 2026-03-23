# Mux No-Arg List Alias Design

**Goal**

Make bare `mux` behave exactly like `mux list` so it is faster to use over SSH, while keeping `mux -h`, `mux --help`, and `mux help` as explicit help entrypoints.

**Scope**

- Treat an empty argv as the same command path as `list`
- Preserve existing selector and session-name behavior for non-empty positional arguments
- Preserve help output for `-h`, `--help`, and `help`
- Update the user-facing README text to document the shortcut

**Architecture**

The change stays in the existing single-file Bash command dispatcher. No tmux, cmux, state, or selector logic changes are needed because `cmd_list` already implements the desired no-arg behavior.

The only behavior change is the top-level `main` case split:

- `""` dispatches to `cmd_list`
- `-h`, `--help`, and `help` dispatch to `usage`
- all existing named subcommands keep their current handlers
- all other tokens still route to bare session selection and launch

**Error Handling**

- Bare `mux` should surface the same command dependency and state errors as `mux list`
- Help flags should continue to print usage without touching list or session logic

**Testing**

Add shell tests that prove:

- `mux` with no args prints the same list-oriented helper output as `mux list`
- `mux -h` and `mux --help` still print usage text
- the existing suite stays green after the dispatch change
