#!/usr/bin/env python3

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

from claude_cmux import build_request


def load_runtime_config() -> dict:
    config_path = Path(__file__).resolve().parent / ".runtime" / "claude-cmux.json"
    if not config_path.exists():
        return {}
    try:
        return json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def main() -> int:
    config = load_runtime_config()
    if not config.get("enabled"):
        return 0

    host_proxy_url = str(config.get("host_proxy_url", "")).strip()
    cmux_socket_path = str(config.get("cmux_socket_path", "")).strip()
    if not host_proxy_url or not cmux_socket_path:
        return 0

    subcommand = sys.argv[1] if len(sys.argv) > 1 else "notification"
    raw_payload = sys.stdin.read()
    try:
        payload = json.loads(raw_payload) if raw_payload.strip() else {}
    except json.JSONDecodeError:
        payload = {}

    try:
        request_payload = build_request(
            subcommand,
            payload,
            cmux_socket_path,
            str(config.get("cmux_workspace_ref", "")).strip() or str(config.get("cmux_workspace_id", "")).strip(),
            str(config.get("cmux_surface_ref", "")).strip() or str(config.get("cmux_surface_id", "")).strip(),
        )
    except ValueError:
        return 0

    request = urllib.request.Request(
        host_proxy_url,
        data=json.dumps(request_payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5):
            return 0
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
