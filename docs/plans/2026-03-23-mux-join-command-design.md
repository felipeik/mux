# mux join Command Design

**Date:** 2026-03-23

**Goal:** add selector-only join commands so users can attach to an existing listed mux entry without ever creating a new tmux session by mistake.

## Decisions

- Add `mux join <selector>` and `mux j <selector>` as explicit join commands.
- Rename the backlog concept from `pick` to `join`; `pick` and `p` are not added.
- `join` is selector-only. It resolves existing mux list entries using the same numeric and letter selectors shown by `mux list`.
- `join` never falls back to a literal tmux session name. If no listed entry matches, it exits non-zero with a clear error.
- `mux join` and `mux j` with no selector become interactive in a real terminal: print the current list, prompt for a selector, then resolve and join it.
- `mux join` and `mux j` with no selector in non-interactive contexts print the current list, print an error explaining that a selector is required, and exit non-zero.
- Bare `mux` remains unchanged in this pass. The later backlog item that changes bare `mux` to help is intentionally out of scope here.

## Command Flow

### `mux join <selector>`

1. Load current mux entries through the existing list source.
2. Resolve the selector against list indexes or letter keys.
3. If a match exists, attach to that entry's tmux session.
4. If no match exists, print an error and exit non-zero.

### `mux join`

1. Load and print the same list output shown by `mux list`.
2. If stdin/stdout are interactive, prompt for a selector.
3. Resolve the entered selector using the same selector rules as `mux join <selector>`.
4. If non-interactive, print an error after the list and exit non-zero instead of waiting forever.

## Error Handling

- Unknown selector: `unknown mux selector: <value>`
- Missing selector in non-interactive mode: `selector required in non-interactive mode`
- Empty interactive input should fail with the same unknown-selector path rather than silently attaching anywhere.

## Testing Scope

- `mux join 1` attaches to the first listed mux session.
- `mux j a` attaches using the letter selector.
- `mux join foo` fails and does not create a new tmux session.
- `mux join 999` fails and does not fall back to a literal tmux session.
- `mux join` in an interactive terminal prints the list, reads a selector, and joins the matched session.
- `mux join` in a non-interactive context prints the list and exits with an error instead of prompting.

## Files

- Update `bin/mux`
- Update `tests/run-tests.sh`
- Update `README.md`
- Update `todo.md`
