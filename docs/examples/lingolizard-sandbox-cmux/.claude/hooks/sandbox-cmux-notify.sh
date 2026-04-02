#!/usr/bin/env bash
set -euo pipefail

command -v python3 >/dev/null 2>&1 || exit 0

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
payload="$(cat)"

printf '%s' "$payload" | python3 "$repo_root/sandbox/claude-cmux-notify.py" "${1:-notification}"
