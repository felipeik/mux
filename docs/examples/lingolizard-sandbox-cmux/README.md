# LingoLizard Sandbox CMUX Example

This directory is a frozen copy of the working sandbox-to-`cmux` notification
implementation from LingoLizard.

Source snapshot:

- repository: `LingoLizard`
- commit: `e292957`
- summary: `feat: forward sandbox Claude notifications to cmux`

Purpose:

- keep a concrete example inside `mux`
- avoid depending on another project staying in sync
- provide real files, not just design notes

Copied files:

- `.claude/settings.json`
- `.claude/hooks/sandbox-cmux-notify.sh`
- `sandbox/claude-cmux-notify.py`
- `sandbox/claude_cmux.py`
- `sandbox/host-proxy.py`
- `sandbox/sandbox.sh`
- `sandbox/tests/test_claude_cmux.py`
- `sandbox/tests/test_host_proxy.py`

What to look at first:

- `.claude/settings.json`
  The project-local `Notification` and `Stop` hooks.
- `.claude/hooks/sandbox-cmux-notify.sh`
  The small shell shim the agent actually runs.
- `sandbox/claude-cmux-notify.py`
  The sandbox relay that reads runtime config and posts to the host.
- `sandbox/claude_cmux.py`
  The request builder that normalizes hook payloads.
- `sandbox/sandbox.sh`
  The launch-time `cmux identify --json --id-format both` capture and runtime file write.
- `sandbox/host-proxy.py`
  The host-side `cmux_notify` action that calls `cmux notify`.

These files are examples, not active `mux` runtime code.
