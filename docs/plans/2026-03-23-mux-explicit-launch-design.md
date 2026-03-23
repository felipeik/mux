# mux Explicit Launch Design

**Date:** 2026-03-23

## Goal

Remove implicit bare-name session launching and standardize mux-managed terminal titles on `mux <name>`.

## Decisions

- Bare `mux <selector>` remains the selector-based join path for existing mux-managed entries.
- Bare `mux <name>` is no longer a launch command. Unmatched bare arguments return an error that directs users to `mux t <name>` or `mux tab <name>`.
- `mux t <name>` and `mux tab <name>` both launch literal tmux session names, including names such as `1` and `a`.
- Both launch commands rename the visible cmux tab to `mux <name>`.
- Saved state, live entry discovery, and restore logic recognize only the canonical `mux <name>` title format.
- Restore respawns panes with an explicit launch command instead of relying on bare-name invocation.

## Rationale

Separating selector-based joins from explicit session creation removes the ambiguous fallback where a missing selector could accidentally create a tmux session. Standardizing titles on `mux <name>` keeps persistence and restore logic simple and removes the legacy split between `mux <name>` and `mux tab <name>`.

## Testing

- Update CLI tests to require `mux t` and `mux tab` for launching.
- Add coverage for literal numeric and letter session names through `mux t`.
- Update save and restore tests to use canonical `mux <name>` titles only.
- Update README assertions to match the new command surface.
