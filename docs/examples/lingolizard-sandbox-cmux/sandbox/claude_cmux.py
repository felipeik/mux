#!/usr/bin/env python3

import os
from typing import Any, Dict, Iterable


def _first_string(payload: Dict[str, Any], key_paths: Iterable[str]) -> str:
    for key_path in key_paths:
        value: Any = payload
        for part in key_path.split("."):
            if not isinstance(value, dict):
                value = ""
                break
            value = value.get(part, "")
        if isinstance(value, str) and value:
            return value
    return ""


def _subtitle_for_message(message: str) -> str:
    lower = message.lower()
    if any(token in lower for token in ("permission", "approve", "approval")):
        return "Permission"
    if any(token in lower for token in ("wait", "input")):
        return "Waiting"
    if any(token in lower for token in ("error", "failed")):
        return "Error"
    return "Attention"


def build_request(
    subcommand: str,
    payload: Dict[str, Any],
    cmux_socket_path: str,
    cmux_workspace_id: str = "",
    cmux_surface_id: str = "",
) -> Dict[str, str]:
    if not cmux_socket_path:
        raise ValueError("cmux_socket_path is required")

    normalized = subcommand.strip().lower()
    if normalized in ("notification", "notify"):
        body = _first_string(
            payload,
            (
                "message",
                "body",
                "text",
                "prompt",
                "error",
                "description",
                "notification.message",
                "notification.body",
                "notification.text",
                "notification.prompt",
                "data.message",
                "data.body",
                "data.text",
                "data.prompt",
            ),
        ) or "Claude needs your attention"
        subtitle = _subtitle_for_message(body)
    elif normalized in ("stop", "idle"):
        body = _first_string(
            payload,
            (
                "stop_hook.active_transcript_path",
                "message",
                "body",
                "text",
            ),
        )
        body = body or "Claude session completed"
        subtitle = "Completed"
        cwd = _first_string(payload, ("cwd",))
        if cwd:
            subtitle = f"Completed in {os.path.basename(cwd.rstrip('/')) or cwd}"
    else:
        raise ValueError("unsupported hook subcommand")

    request = {
        "action": "cmux_notify",
        "title": "Claude Code",
        "subtitle": subtitle,
        "body": body,
        "cmux_socket_path": cmux_socket_path,
    }
    if cmux_workspace_id:
        request["cmux_workspace_id"] = cmux_workspace_id
    if cmux_surface_id:
        request["cmux_surface_id"] = cmux_surface_id
    return request
