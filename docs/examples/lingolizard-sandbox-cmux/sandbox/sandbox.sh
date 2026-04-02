#!/bin/bash
# ── LingoLizard Docker Sandbox Manager ───────────────────────────────────────
# Usage: ./sandbox/sandbox.sh <command> [options]
#
# Commands:
#   init          Build the Docker sandbox image
#   proxy         Start the host proxy (foreground, Ctrl+C to stop)
#   run           Launch or resume a sandbox (resumes existing by default)
#   status        Show what's running
#
# Options:
#   --port PORT       Host proxy port (default: 9007)
#   --name NAME       Sandbox name (default: claude-<project>)
#   --gh-token TOKEN  GitHub PAT to pass into sandbox
#   -h, --help        Show this help
#
# Workflow:
#   Terminal 1:  ./sandbox/sandbox.sh proxy             # host proxy (stays open)
#   Terminal 2:  ./sandbox/sandbox.sh run               # sandbox (resumes if exists)
#   Ctrl+C in Terminal 2 exits the sandbox session
#   Ctrl+C in Terminal 1 kills the proxy (sandbox loses host access)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve to the main repo root (not a worktree path)
_git_common="$(cd "$SCRIPT_DIR/.." && git rev-parse --git-common-dir 2>/dev/null)"
if [ -n "$_git_common" ] && [ "$_git_common" != ".git" ]; then
    # We're in a worktree — common dir is /path/to/repo/.git
    PROJECT_ROOT="$(cd "$(dirname "$_git_common")" && pwd)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
IMAGE_NAME="lingolizard-sandbox:v1"
PROXY_PORT=9007
GH_TOKEN=""
SANDBOX_NAME=""

# ── Colors (disabled when not a TTY) ─────────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log()  { echo -e "${BLUE}[sandbox]${NC} $*"; }
ok()   { echo -e "${GREEN}[sandbox]${NC} $*"; }
warn() { echo -e "${YELLOW}[sandbox]${NC} $*"; }
err()  { echo -e "${RED}[sandbox]${NC} $*" >&2; }

# ── Helpers ──────────────────────────────────────────────────────────────────

usage() {
    sed -n '2,/^[^#]/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
    exit 0
}

check_deps() {
    local missing=()
    for cmd in docker python3 jq curl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if ! docker sandbox version &>/dev/null; then
        missing+=("docker sandbox (Docker Desktop with sandbox support)")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

proxy_listening() {
    # GET / returns 200 from the health check endpoint
    curl -sf -o /dev/null --max-time 1 "http://localhost:$PROXY_PORT" 2>/dev/null
}

# ── Commands ─────────────────────────────────────────────────────────────────

cmd_init() {
    check_deps
    log "Building sandbox image: $IMAGE_NAME"
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR/"
    ok "Image built: $IMAGE_NAME"
    echo ""
    log "Next steps:"
    log "  Terminal 1: ./sandbox/sandbox.sh proxy"
    log "  Terminal 2: ./sandbox/sandbox.sh run"
}

cmd_proxy() {
    log "Starting host proxy on :$PROXY_PORT (project: $PROJECT_ROOT)"
    log "Press Ctrl+C to stop"
    echo ""
    python3 "$SCRIPT_DIR/host-proxy.py" \
        --port "$PROXY_PORT" \
        --project-root "$PROJECT_ROOT"
}

sandbox_exists() {
    docker sandbox ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$1"
}

# Find existing sandbox using the same workspace path (Docker allows only one per workspace)
sandbox_for_workspace() {
    local ws="$1"
    docker sandbox ls 2>/dev/null | awk -v ws="$ws" 'NR>1 && $NF == ws {print $1}'
}

cmd_run() {
    check_deps
    local runtime_dir runtime_config network_proxy_pid=""
    local cmux_identify_json="" cmux_workspace_ref="" cmux_surface_ref=""

    # Check proxy is reachable
    if ! proxy_listening; then
        err "Proxy not reachable on localhost:$PROXY_PORT"
        err "Start it first: ./sandbox/sandbox.sh proxy"
        exit 1
    fi
    ok "Proxy reachable on :$PROXY_PORT"

    # Default name
    if [ -z "$SANDBOX_NAME" ]; then
        SANDBOX_NAME="claude-$(basename "$PROJECT_ROOT")"
    fi

    # Build sandbox args depending on whether it already exists
    local sandbox_args=()
    if sandbox_exists "$SANDBOX_NAME"; then
        log "Resuming existing sandbox: $SANDBOX_NAME"
        sandbox_args=(sandbox run "$SANDBOX_NAME")
    else
        # Docker allows only one sandbox per workspace — check if another sandbox owns it
        local existing
        existing=$(sandbox_for_workspace "$PROJECT_ROOT")
        if [ -n "$existing" ]; then
            if [ "$existing" != "$SANDBOX_NAME" ]; then
                warn "Workspace already used by sandbox '$existing'"
                log "Resuming '$existing' instead (Docker allows one sandbox per workspace)"
                SANDBOX_NAME="$existing"
                sandbox_args=(sandbox run "$SANDBOX_NAME")
            fi
        fi

        # Create new sandbox if no existing one was found
        if [ ${#sandbox_args[@]} -eq 0 ]; then
            if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
                err "Image $IMAGE_NAME not found. Run: ./sandbox/sandbox.sh init"
                exit 1
            fi
            log "Creating new sandbox: $SANDBOX_NAME"
            sandbox_args=(sandbox run --template "$IMAGE_NAME" --name "$SANDBOX_NAME")
            sandbox_args+=(claude "$PROJECT_ROOT")
            # Mount ~/.claude read-write so sandbox can read skills/settings and
            # write plans, paste-cache (text), and other session state.
            # Use explicit dest /home/agent/.claude — the Dockerfile symlinks
            # /Users/felipeiketani → /home/agent, but Docker mounts don't follow
            # symlinks, so without an explicit dest the agent's ~ writes go to
            # the in-container /home/agent/.claude, not the mounted volume.
            local claude_home="$HOME/.claude"
            if [ -d "$claude_home" ]; then
                sandbox_args+=("$claude_home")
                log "Mounting $claude_home (read-write)"
            fi
            # Mount macOS temp dir read-only so pasted images (clipboard-*.png) are accessible.
            # Claude Code saves image pastes to $TMPDIR on the host, not to ~/.claude.
            local tmpdir="${TMPDIR:-/tmp}"
            tmpdir="${tmpdir%/}"  # strip trailing slash
            if [ -d "$tmpdir" ]; then
                sandbox_args+=("${tmpdir}:ro")
                log "Mounting $tmpdir (read-only, image pastes)"
            fi
        fi
    fi

    runtime_dir="$SCRIPT_DIR/.runtime"
    runtime_config="$runtime_dir/claude-cmux.json"
    mkdir -p "$runtime_dir"
    if [ -n "${CMUX_SOCKET_PATH:-}" ]; then
        if command -v cmux >/dev/null 2>&1; then
            cmux_identify_json="$(cmux identify --json --id-format both 2>/dev/null || true)"
        fi
        if [ -n "$cmux_identify_json" ]; then
            cmux_workspace_ref="$(printf '%s' "$cmux_identify_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("focused", {}).get("workspace_ref", ""))' 2>/dev/null || true)"
            cmux_surface_ref="$(printf '%s' "$cmux_identify_json" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("focused", {}).get("surface_ref", ""))' 2>/dev/null || true)"
        fi
        local cmux_workspace_json cmux_surface_json cmux_workspace_ref_json cmux_surface_ref_json
        cmux_workspace_json="$(printf '%s' "${CMUX_WORKSPACE_ID:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
        cmux_surface_json="$(printf '%s' "${CMUX_SURFACE_ID:-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
        cmux_workspace_ref_json="$(printf '%s' "$cmux_workspace_ref" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
        cmux_surface_ref_json="$(printf '%s' "$cmux_surface_ref" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
        cat >"$runtime_config" <<EOF
{"enabled":true,"host_proxy_url":"http://host.docker.internal:$PROXY_PORT","cmux_socket_path":"$CMUX_SOCKET_PATH","cmux_workspace_id":$cmux_workspace_json,"cmux_surface_id":$cmux_surface_json,"cmux_workspace_ref":$cmux_workspace_ref_json,"cmux_surface_ref":$cmux_surface_ref_json}
EOF
        log "CMUX notifications enabled for socket $CMUX_SOCKET_PATH"
        if [ -n "$cmux_workspace_ref" ] && [ -n "$cmux_surface_ref" ]; then
            log "CMUX notification target: $cmux_workspace_ref / $cmux_surface_ref"
        else
            warn "Could not resolve CMUX workspace/surface refs via cmux identify; notify targeting may fail"
        fi
    else
        rm -f "$runtime_config"
        warn "CMUX_SOCKET_PATH not set on host; sandbox Claude notifications will be disabled"
    fi

    # GH_TOKEN forwarding is not wired through the docker sandbox CLI yet.
    # Keep the flag visible to the user instead of passing unsupported agent args.
    if [ -n "$GH_TOKEN" ]; then
        warn "GH_TOKEN forwarding is not currently supported by docker sandbox run; ignoring --gh-token"
    fi

    # Allow network access to host proxy after sandbox starts
    (
        sleep 3
        docker sandbox network proxy "$SANDBOX_NAME" \
            --allow-host "localhost:$PROXY_PORT" 2>/dev/null || true
        ok "Network: allowed localhost:$PROXY_PORT for $SANDBOX_NAME"
    ) &
    network_proxy_pid="$!"

    # Clean up all background jobs on exit
    trap 'if [ -n "'"$network_proxy_pid"'" ]; then kill "'"$network_proxy_pid"'" 2>/dev/null || true; fi' EXIT

    # Launch sandbox — blocks until Claude exits
    docker "${sandbox_args[@]}" || true
    trap - EXIT
    log "Sandbox $SANDBOX_NAME exited"
}

cmd_status() {
    echo ""
    if proxy_listening; then
        ok "Proxy: listening on :$PROXY_PORT"
    else
        warn "Proxy: not reachable on :$PROXY_PORT"
    fi

    if docker image inspect "$IMAGE_NAME" &>/dev/null; then
        ok "Image: $IMAGE_NAME exists"
    else
        warn "Image: $IMAGE_NAME not found (run: sandbox.sh init)"
    fi

    # List running sandboxes
    local sandboxes
    sandboxes=$(docker sandbox ls 2>/dev/null | grep -v "^NAME" || true)
    if [ -n "$sandboxes" ]; then
        ok "Sandboxes:"
        echo "$sandboxes" | while read -r line; do
            echo "  $line"
        done
    else
        warn "Sandboxes: none running"
    fi
    echo ""
}

# ── Argument parsing ─────────────────────────────────────────────────────────

COMMAND=""

while [ $# -gt 0 ]; do
    case "$1" in
        init|proxy|run|status)
            COMMAND="$1"
            ;;
        --port)
            PROXY_PORT="${2:?--port requires a value}"
            shift
            ;;
        --name)
            SANDBOX_NAME="${2:?--name requires a value}"
            shift
            ;;
        --gh-token)
            GH_TOKEN="${2:?--gh-token requires a value}"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            err "Unknown argument: $1"
            usage
            ;;
    esac
    shift
done

if [ -z "$COMMAND" ]; then
    err "No command specified"
    usage
fi

"cmd_$COMMAND"
