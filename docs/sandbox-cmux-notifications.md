# CMUX Notifications from Host Agents and Docker Sandboxes

This document captures the pattern that worked for routing agent notifications
back to `cmux`, including when the agent runs inside `tmux` or inside a Docker
sandbox.

It is intended as reusable guidance for future projects.

A concrete copied example lives in
[`docs/examples/lingolizard-sandbox-cmux`](examples/lingolizard-sandbox-cmux/README.md).

## Supported Launch Shapes

- `cmux > agent`
- `cmux > tmux > agent`
- `cmux > sandbox`
- `cmux > tmux > sandbox`

Where:

- `agent` means a host process
- `sandbox` means a containerized agent process
- `proxy` means a host-side bridge process a sandbox can call

## Core Principle

Separate these responsibilities:

1. Event source
- The agent must emit a hook or notification event.
- Install hooks where the agent actually runs.

2. Delivery
- The event must reach `cmux notify` on the host, targeted at the right tab.

Do not assume that solving transport also creates the event, or that installing
hooks on the host makes them fire inside a container.

## Recommended Architectures

### Host agent

```text
agent hook -> mux-agent-notify -> cmux notify
```

This is the normal `mux init` case.

### Sandboxed agent

```text
agent hook in sandbox -> sandbox relay -> host proxy -> cmux notify
```

This is the reliable pattern for containers.

`mux-agent-notify` by itself is host-oriented. It does not solve the
container-to-host bridge.

## Topology Guidance

### `cmux > agent`

Best case.

- The hook can notify `cmux` directly.
- `mux-agent-notify` is usually enough.

### `cmux > tmux > agent`

Still straightforward.

- `mux-agent-notify` can use tmux OSC passthrough so notifications reach `cmux`.
- Targeting is still derived from the `cmux` shell ancestry.

### `cmux > sandbox`

Use a host bridge.

Recommended flow:

```text
sandbox hook -> HTTP or socket relay -> host proxy -> cmux notify
```

Do not try to call host `cmux` directly from inside the container.

### `cmux > tmux > sandbox`

Use:

```text
cmux > tmux > proxy
cmux > tmux > sandbox
```

The sandbox launcher determines where notification clicks should return.

The proxy can be long-lived, but it must not target its own tab by accident.

## Launch-Time Target Capture

When launching the agent or sandbox from a `cmux` shell, capture:

- `CMUX_SOCKET_PATH`
- `workspace_ref`
- `surface_ref`

Use:

```bash
cmux identify --json --id-format both
```

Persist the values in a runtime file that the hook process can read later.

Important:

- prefer `workspace:4` / `surface:13` style refs
- do not rely on raw UUID-style env IDs for CLI targeting

## Runtime File Rule

The launcher and the hook must agree on the same runtime file path.

Common failure mode:

- launcher writes runtime config in one repo or worktree
- agent loads hooks from another repo or worktree
- hook fires, but cannot find its runtime config

If worktrees are involved, be explicit about which tree owns:

- hook config
- runtime config
- sandbox launcher

## Host Proxy Requirements

For sandboxes, expose one narrow host-side action, for example:

```json
{
  "action": "cmux_notify",
  "title": "Claude Code",
  "subtitle": "Completed",
  "body": "Claude session completed",
  "cmux_socket_path": "/path/to/cmux.sock",
  "cmux_workspace_id": "workspace:4",
  "cmux_surface_id": "surface:13"
}
```

The proxy should:

- validate required fields
- sanitize title, subtitle, and body
- run `cmux notify` with `shell=False`
- pass `--workspace` and `--surface` explicitly
- set `CMUX_SOCKET_PATH`
- clear inherited `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, and `CMUX_TAB_ID`

Do not expose arbitrary `cmux` shell execution to the sandbox.

## CMUX Socket Control Mode

If you want a long-lived proxy in `cmux > tmux > proxy`, ancestry-restricted
socket access can block it.

For that model, use `cmux`:

- `Settings`
- `Automation`
- `Socket Control Mode`
- `Full Open Access`

Why:

- ancestry-only access can fail for a persistent tmux-hosted proxy
- `Full Open Access` removes that restriction

Tradeoff:

- this opens the `cmux` socket to local users and processes on the machine
- only use it if that risk is acceptable in your environment

## Common Failure Modes

### Hook inspector shows the hook, but nothing reaches the proxy

Likely causes:

- the hook exits early
- the runtime file is missing
- the hook is loaded from a different repo or worktree than the launcher

### Proxy receives the request, but `cmux notify` says `Tab not found`

Likely cause:

- raw UUIDs were forwarded instead of `workspace:N` / `surface:N`

### Proxy receives the request, but `cmux notify` says access denied

Likely cause:

- `cmux` socket control mode is still ancestry-restricted

### Notification opens the proxy tab instead of the agent tab

Likely causes:

- the proxy used its own inherited `CMUX_*` env
- the launcher did not forward launch-time `workspace_ref` / `surface_ref`

### Manual synthetic notification works, but real hook events do not

Likely causes:

- the wrong config scope is active
- a global agent config overrides the project hook
- the running agent process has not reloaded changed hook config

## Minimal Checklist for a New Project

1. Install hooks in the agent runtime, not just on the host.
2. Decide whether the agent is host-native or sandboxed.
3. For sandboxes, add a narrow host proxy action for notifications.
4. Capture `CMUX_SOCKET_PATH`, `workspace_ref`, and `surface_ref` at launch.
5. Write them to a runtime file the hook can read.
6. In the proxy, call `cmux notify --workspace ... --surface ...`.
7. If using `cmux > tmux > proxy`, enable `Full Open Access` in `cmux`.
8. Test with both:
- a synthetic payload
- a real completion or needs-attention event

## Where `mux` Fits

`mux` already handles the host-side notification path for supported agent CLIs
when they run in:

- plain `cmux`
- `tmux` inside `cmux`

For Docker sandboxes, `mux` is still useful as the target notification model,
but the sandbox project must add its own relay and host proxy integration.
