#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT_DIR/tests/helpers/assert.sh"

make_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/mux-tests.XXXXXX"
}

write_executable() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat >"$path"
  chmod +x "$path"
}

test_cli_help_flags_print_usage() {
  local short_output long_output alias_output help_output
  short_output="$("$ROOT_DIR/bin/mux" -h 2>&1 || true)"
  long_output="$("$ROOT_DIR/bin/mux" --help 2>&1 || true)"
  alias_output="$("$ROOT_DIR/bin/mux" h 2>&1 || true)"
  help_output="$("$ROOT_DIR/bin/mux" help 2>&1 || true)"
  assert_contains "usage" "$short_output" "expected mux -h output"
  assert_contains "usage" "$long_output" "expected mux --help output"
  assert_contains "usage" "$alias_output" "expected mux h output"
  assert_contains "usage" "$help_output" "expected mux help output"
}

test_mux_with_no_args_prints_usage() {
  local output
  output="$("$ROOT_DIR/bin/mux" 2>&1 || true)"
  assert_contains "usage: mux" "$output" "expected bare mux to print usage"
  assert_contains "init [claude|codex]" "$output" "expected mux usage to include init"
  assert_contains "uninstall [claude|codex]" "$output" "expected mux usage to include uninstall"
  assert_contains "list, l" "$output" "expected grouped list alias in usage"
  assert_contains "restore, r" "$output" "expected grouped restore alias in usage"
  case "$output" in
    *"Workspace  Session"*)
      fail "expected bare mux to print usage instead of the list table"
      ;;
  esac
}

test_mux_l_alias_matches_mux_list() {
  local temp_dir stub_dir alias_output list_output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  alias_output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" l 2>&1 || true)"
  list_output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" list 2>&1 || true)"

  assert_eq "$list_output" "$alias_output" "expected mux l to match mux list output"
  assert_contains "Workspace  Session" "$alias_output" "expected mux l to show the list table"
}

test_mux_r_alias_matches_mux_restore() {
  local temp_dir stub_dir state_file alias_output restore_output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  state_file="$temp_dir/state.json"
  mkdir -p "$stub_dir"

  cat >"$state_file" <<'EOF'
{"version":1,"workspaces":[]}
EOF

  write_executable "$stub_dir/cmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tree" ] && [ "$2" = "--all" ] && [ "$3" = "--json" ]; then
  cat <<'OUT'
{"windows":[]}
OUT
  exit 0
fi
exit 0
EOF

  alias_output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" r 2>&1 || true)"
  restore_output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" restore 2>&1 || true)"

  assert_eq "$restore_output" "$alias_output" "expected mux r to match mux restore output"
}

test_mux_init_claude_installs_global_hooks() {
  local temp_dir home_dir stub_dir output helper_path settings_path summary
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  stub_dir="$temp_dir/bin"
  helper_path="$home_dir/.local/bin/mux-agent-notify"
  settings_path="$home_dir/.claude/settings.json"
  mkdir -p "$home_dir/.claude" "$stub_dir"

  cat >"$settings_path" <<'EOF'
{
  "model": "haiku",
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bd prime"
          }
        ]
      }
    ]
  }
}
EOF

  write_executable "$stub_dir/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  output="$(HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" init claude 2>&1 || true)"

  assert_contains "installed claude hooks" "$output" "expected mux init claude to report installation"
  assert_contains "$settings_path" "$output" "expected mux init claude to print the Claude settings path"
  assert_contains "$helper_path" "$output" "expected mux init claude to print the helper path"
  if [ ! -x "$helper_path" ]; then
    fail "expected mux init claude to create an executable helper script"
  fi

  summary="$(python3 - <<'PY' "$settings_path"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
hooks = data.get('hooks', {})
checks = [
    data.get('model') == 'haiku',
    hooks.get('PreCompact', [{}])[0].get('hooks', [{}])[0].get('command') == 'bd prime',
    any(h.get('command', '').endswith('mux-agent-notify claude-hook notification') for g in hooks.get('Notification', []) for h in g.get('hooks', [])),
    any(h.get('command', '').endswith('mux-agent-notify claude-hook stop') for g in hooks.get('Stop', []) for h in g.get('hooks', [])),
    any(h.get('command', '').endswith('mux-agent-notify claude-hook session-end') for g in hooks.get('SessionEnd', []) for h in g.get('hooks', [])),
    any(h.get('command', '').endswith('mux-agent-notify claude-hook prompt-submit') for g in hooks.get('UserPromptSubmit', []) for h in g.get('hooks', [])),
    any(h.get('command', '').endswith('mux-agent-notify claude-hook pre-tool-use') and h.get('async') is True for g in hooks.get('PreToolUse', []) for h in g.get('hooks', [])),
]
print('ok' if all(checks) else 'bad')
PY
)"
  assert_eq "ok" "$summary" "expected mux init claude to merge the supported hooks into ~/.claude/settings.json"
}

test_mux_init_claude_project_scope_installs_project_hooks() {
  local temp_dir home_dir project_dir stub_dir output helper_path settings_path summary
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  project_dir="$temp_dir/project"
  stub_dir="$temp_dir/bin"
  helper_path="$home_dir/.local/bin/mux-agent-notify"
  settings_path="$project_dir/.claude/settings.json"
  mkdir -p "$home_dir" "$project_dir" "$stub_dir"
  project_dir="$(cd "$project_dir" && pwd -P)"
  settings_path="$project_dir/.claude/settings.json"

  write_executable "$stub_dir/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  output="$(cd "$project_dir" && HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" init claude --scope project 2>&1 || true)"

  assert_contains "installed claude hooks" "$output" "expected project-scope install to report success"
  assert_contains "$settings_path" "$output" "expected project-scope install to print the project Claude settings path"
  assert_contains "$helper_path" "$output" "expected project-scope install to print the helper path"

  summary="$(python3 - <<'PY' "$settings_path"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
hooks = data.get('hooks', {})
checks = [
    any(h.get('command', '').endswith('mux-agent-notify claude-hook notification') for g in hooks.get('Notification', []) for h in g.get('hooks', [])),
    any(h.get('command', '').endswith('mux-agent-notify claude-hook stop') for g in hooks.get('Stop', []) for h in g.get('hooks', [])),
]
print('ok' if all(checks) else 'bad')
PY
)"
  assert_eq "ok" "$summary" "expected project-scope install to write Claude hooks into .claude/settings.json"
}

test_mux_init_helper_writes_tmux_notifications_to_tty() {
  local temp_dir home_dir stub_dir helper_path tty_path output tty_output
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  stub_dir="$temp_dir/bin"
  helper_path="$home_dir/.local/bin/mux-agent-notify"
  tty_path="$temp_dir/fake-tty"
  mkdir -p "$home_dir" "$stub_dir"

  write_executable "$stub_dir/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" init claude >/dev/null 2>&1 || true

  output="$(printf '{"message":"manual helper notification"}' \
    | HOME="$home_dir" TMUX=1 CMUX_SURFACE_ID=surface-1 MUX_AGENT_NOTIFY_TTY_PATH="$tty_path" "$helper_path" claude-hook notification)"
  tty_output="$(cat "$tty_path" 2>/dev/null || true)"

  assert_eq "" "$output" "expected tmux hook notifications to avoid stdout so Claude cannot capture the OSC payload"
  assert_contains "]777;notify;Claude Code;Attention: manual helper notification" "$tty_output" "expected tmux hook notifications to be written to the pane tty"
}

test_mux_uninstall_claude_removes_user_project_and_local_project_hooks() {
  local temp_dir home_dir project_dir project_dir_real stub_dir helper_path user_settings_path project_settings_path local_project_settings_path output summary
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  project_dir="$temp_dir/project"
  stub_dir="$temp_dir/bin"
  helper_path="$home_dir/.local/bin/mux-agent-notify"
  user_settings_path="$home_dir/.claude/settings.json"
  mkdir -p "$home_dir/.claude" "$project_dir/.claude" "$stub_dir"
  project_dir_real="$(cd "$project_dir" && pwd -P)"
  project_settings_path="$project_dir_real/.claude/settings.json"
  local_project_settings_path="$project_dir_real/.claude/settings.local.json"

  cat >"$user_settings_path" <<EOF
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bd prime"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$helper_path claude-hook notification"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$helper_path claude-hook stop"
          }
        ]
      }
    ]
  }
}
EOF

  cat >"$project_settings_path" <<EOF
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$helper_path claude-hook notification"
          }
        ]
      }
    ]
  }
}
EOF

  cat >"$local_project_settings_path" <<EOF
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$helper_path claude-hook stop"
          }
        ]
      }
    ]
  }
}
EOF

  output="$(cd "$project_dir_real" && HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" uninstall claude 2>&1 || true)"

  assert_contains "removed claude hooks" "$output" "expected mux uninstall claude to report removal"
  assert_contains "$user_settings_path" "$output" "expected mux uninstall claude to print the user Claude settings path"
  assert_contains "$project_settings_path" "$output" "expected mux uninstall claude to print the project Claude settings path"
  assert_contains "$local_project_settings_path" "$output" "expected mux uninstall claude to print the local-project Claude settings path"

  summary="$(python3 - <<'PY' "$user_settings_path" "$project_settings_path" "$local_project_settings_path"
import json, sys

def load(path):
    with open(path, 'r', encoding='utf-8') as fh:
        return json.load(fh)

user_data = load(sys.argv[1])
project_data = load(sys.argv[2])
local_data = load(sys.argv[3])

user_hooks = user_data.get('hooks', {})
project_hooks = project_data.get('hooks', {})
local_hooks = local_data.get('hooks', {})

checks = [
    user_hooks.get('PreCompact', [{}])[0].get('hooks', [{}])[0].get('command') == 'bd prime',
    not user_hooks.get('Notification'),
    not user_hooks.get('Stop'),
    not project_hooks.get('Notification'),
    not local_hooks.get('Stop'),
]
print('ok' if all(checks) else 'bad')
PY
)"
  assert_eq "ok" "$summary" "expected mux uninstall claude to remove mux-managed Claude hooks from user, project, and local-project scopes"
}

test_mux_init_codex_installs_global_hooks() {
  local temp_dir home_dir stub_dir output helper_path config_path hooks_path summary
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  stub_dir="$temp_dir/bin"
  helper_path="$home_dir/.local/bin/mux-agent-notify"
  config_path="$home_dir/.codex/config.toml"
  hooks_path="$home_dir/.codex/hooks.json"
  mkdir -p "$home_dir/.codex" "$stub_dir"

  cat >"$config_path" <<'EOF'
model = "gpt-5.4"
personality = "pragmatic"
EOF

  write_executable "$stub_dir/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  output="$(HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" init codex 2>&1 || true)"

  assert_contains "installed codex hooks" "$output" "expected mux init codex to report installation"
  assert_contains "$hooks_path" "$output" "expected mux init codex to print the Codex hooks path"
  assert_contains "$config_path" "$output" "expected mux init codex to print the Codex config path"
  assert_contains "$helper_path" "$output" "expected mux init codex to print the helper path"
  if [ ! -x "$helper_path" ]; then
    fail "expected mux init codex to create an executable helper script"
  fi
  assert_contains "codex_hooks = true" "$(cat "$config_path")" "expected mux init codex to enable codex hooks in config.toml"
  assert_contains "model = \"gpt-5.4\"" "$(cat "$config_path")" "expected mux init codex to preserve existing config values"

  summary="$(python3 - <<'PY' "$hooks_path"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
hooks = data.get('hooks', {})
checks = [
    any(h.get('command', '').endswith('mux-agent-notify codex-hook session-start') for g in hooks.get('SessionStart', []) for h in g.get('hooks', [])),
    any(h.get('command', '').endswith('mux-agent-notify codex-hook prompt-submit') for g in hooks.get('UserPromptSubmit', []) for h in g.get('hooks', [])),
    any(h.get('command', '').endswith('mux-agent-notify codex-hook stop') for g in hooks.get('Stop', []) for h in g.get('hooks', [])),
]
print('ok' if all(checks) else 'bad')
PY
)"
  assert_eq "ok" "$summary" "expected mux init codex to write the cmux-compatible global hook file"
}

test_mux_uninstall_codex_removes_only_mux_hooks_and_feature_flag() {
  local temp_dir home_dir stub_dir helper_path config_path hooks_path output summary
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  stub_dir="$temp_dir/bin"
  helper_path="$home_dir/.local/bin/mux-agent-notify"
  config_path="$home_dir/.codex/config.toml"
  hooks_path="$home_dir/.codex/hooks.json"
  mkdir -p "$home_dir/.codex" "$home_dir/.local/bin" "$stub_dir"

  cat >"$config_path" <<'EOF'
model = "gpt-5.4"

[features]
codex_hooks = true
EOF

  cat >"$hooks_path" <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$helper_path codex-hook session-start"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$helper_path codex-hook stop"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$helper_path codex-hook prompt-submit"
          }
        ]
      }
    ]
  }
}
EOF

  output="$(HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" uninstall codex 2>&1 || true)"

  assert_contains "removed codex hooks" "$output" "expected mux uninstall codex to report removal"
  assert_contains "$hooks_path" "$output" "expected mux uninstall codex to print the Codex hooks path"
  assert_contains "$config_path" "$output" "expected mux uninstall codex to print the Codex config path"

  summary="$(python3 - <<'PY' "$hooks_path" "$config_path"
import json, sys
hooks_path, config_path = sys.argv[1], sys.argv[2]
with open(hooks_path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)
hooks = data.get('hooks', {})
config = open(config_path, 'r', encoding='utf-8').read()
checks = [
    not hooks.get('SessionStart'),
    not hooks.get('Stop'),
    not hooks.get('UserPromptSubmit'),
    'codex_hooks = true' not in config,
]
print('ok' if all(checks) else 'bad')
PY
)"
  assert_eq "ok" "$summary" "expected mux uninstall codex to remove mux-managed Codex hooks and disable the feature flag when nothing remains"
}

test_mux_init_codex_rejects_project_scope() {
  local temp_dir home_dir project_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  project_dir="$temp_dir/project"
  stub_dir="$temp_dir/bin"
  mkdir -p "$home_dir" "$project_dir" "$stub_dir"

  write_executable "$stub_dir/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  output="$(cd "$project_dir" && HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" init codex --scope project 2>&1 || true)"

  assert_contains "codex only supports --scope user" "$output" "expected project-scope Codex install to explain the unsupported scope"
}

test_mux_init_all_skips_missing_apps() {
  local temp_dir home_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  home_dir="$temp_dir/home"
  stub_dir="$temp_dir/bin"
  mkdir -p "$home_dir" "$stub_dir"

  output="$(HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$ROOT_DIR/bin/mux" init 2>&1 || true)"

  assert_contains "skipping claude: not installed" "$output" "expected mux init to skip claude when it is missing"
  assert_contains "skipping codex: not installed" "$output" "expected mux init to skip codex when it is missing"
  if [ -e "$home_dir/.local/bin/mux-agent-notify" ]; then
    fail "expected mux init to avoid writing helper files when no supported apps are installed"
  fi
}

test_install_claude_sandbox_allows_configured_host_ports() {
  local temp_dir project_dir home_dir stub_dir docker_log output sandbox_name sandbox_script env_file
  temp_dir="$(make_temp_dir)"
  project_dir="$temp_dir/project"
  home_dir="$temp_dir/home"
  stub_dir="$temp_dir/bin"
  docker_log="$temp_dir/docker.log"
  mkdir -p "$project_dir" "$home_dir/.claude" "$stub_dir"

  "$ROOT_DIR/bin/install-claude-sandbox" "$project_dir" >/dev/null

  sandbox_script="$project_dir/sandbox/sandbox.sh"
  env_file="$project_dir/sandbox/.env"
  sandbox_name="claude-project"

  cat >"$env_file" <<'EOF'
SANDBOX_PROXY_PORT=9007
SANDBOX_ALLOWED_HOST_PORTS=5433,6380
EOF

  write_executable "$stub_dir/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$docker_log"
if [ "\$1" = "sandbox" ] && [ "\$2" = "version" ]; then
  exit 0
fi
if [ "\$1" = "sandbox" ] && [ "\$2" = "ls" ]; then
  printf 'NAME STATUS WORKSPACE\n'
  exit 0
fi
if [ "\$1" = "image" ] && [ "\$2" = "inspect" ]; then
  exit 0
fi
if [ "\$1" = "sandbox" ] && [ "\$2" = "run" ]; then
  exit 0
fi
if [ "\$1" = "sandbox" ] && [ "\$2" = "network" ] && [ "\$3" = "proxy" ]; then
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  write_executable "$stub_dir/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  output="$(HOME="$home_dir" PATH="$stub_dir:/usr/bin:/bin" "$sandbox_script" run 2>&1 || true)"

  assert_contains "Proxy reachable on :9007" "$output" "expected generated sandbox to accept the configured proxy port"
  assert_file_exists "$docker_log"
  assert_contains "sandbox network proxy $sandbox_name --allow-host localhost:9007 --allow-host localhost:5433 --allow-host localhost:6380" "$(cat "$docker_log")" "expected generated sandbox to allow each configured host port"
}

test_tab_uses_tmux_new_session_and_renames_cmux_tab() {
  local temp_dir stub_dir log_file
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
EOF

  PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" tab claude-123 || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux claude-123" "$(cat "$log_file")" "expected canonical cmux tab rename"
  assert_contains "tmux:new-session -A -s claude-123" "$(cat "$log_file")" "expected tmux new-session -A -s"
}

test_t_uses_tmux_new_session_and_renames_cmux_tab() {
  local temp_dir stub_dir log_file
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
EOF

  PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" t claude-123 || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux claude-123" "$(cat "$log_file")" "expected cmux tab rename for t"
  assert_contains "tmux:new-session -A -s claude-123" "$(cat "$log_file")" "expected tmux new-session -A -s for t"
}

test_mux_tab_rejects_control_characters_in_session_name() {
  local temp_dir stub_dir output log_file name esc
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
EOF

  name="$(printf 'bad\033[31mred')"
  esc="$(printf '\033')"

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" tab "$name" 2>&1 || true)"

  assert_contains "invalid session name: bad?[31mred" "$output" "expected mux tab to reject control characters with sanitized output"
  case "$output" in
    *"$esc"*)
      fail "expected mux tab rejection output to avoid raw escape bytes"
      ;;
  esac
  if [ -f "$log_file" ]; then
    fail "expected mux tab to reject invalid session name before calling tmux or cmux"
  fi
}

test_bare_name_requires_explicit_launch_command() {
  local temp_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  mkdir -p "$stub_dir"

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
exit 1
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
exit 0
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" backend 2>&1 || true)"
  assert_contains "usage: mux" "$output" "expected bare deprecated launch to print usage"
}

test_mux_t_launch_persists_before_entering_tmux() {
  local temp_dir stub_dir log_file tree_json
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  tree_json="$temp_dir/tree.json"
  mkdir -p "$stub_dir"

  cat >"$tree_json" <<'EOF'
{"windows":[]}
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
cat
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$tree_json"
  exit 0
fi
exit 0
EOF

  PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" t backend || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux backend" "$(cat "$log_file")" "expected tab rename before launch"
  assert_contains "cmux:tree --all --json" "$(cat "$log_file")" "expected persist tree snapshot before tmux launch"
  assert_contains "tmux:new-session -A -s backend" "$(cat "$log_file")" "expected tmux new-session for t launch"
}

test_mux_tab_launch_persists_before_entering_tmux() {
  local temp_dir stub_dir log_file tree_json
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  tree_json="$temp_dir/tree.json"
  mkdir -p "$stub_dir"

  cat >"$tree_json" <<'EOF'
{"windows":[]}
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
cat
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$tree_json"
  exit 0
fi
exit 0
EOF

  PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" tab backend || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux backend" "$(cat "$log_file")" "expected canonical tab rename before launch"
  assert_contains "cmux:tree --all --json" "$(cat "$log_file")" "expected persist tree snapshot before tmux launch"
  assert_contains "tmux:new-session -A -s backend" "$(cat "$log_file")" "expected tmux new-session for tab launch"
}

test_launch_commands_treat_literal_names_as_session_names() {
  local temp_dir stub_dir log_file output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" t 1 2>&1 || true)"
  case "$output" in
    *"integer"*)
      fail "expected mux t 1 to be treated as a valid session name"
      ;;
  esac
  PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" t a || true

  PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" tab api-1 || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s 1" "$(cat "$log_file")" "expected mux t 1 to launch session 1"
  assert_contains "tmux:new-session -A -s a" "$(cat "$log_file")" "expected mux t a to launch session a"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux api-1" "$(cat "$log_file")" "expected canonical session rename"
  assert_contains "tmux:new-session -A -s api-1" "$(cat "$log_file")" "expected mux tab api-1 to launch session api-1"
}

test_mux_list_prints_numbered_mux_tabs_only() {
  local temp_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Beta",
          "panes": [
            {
              "index": 1,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "lazygit",
                  "index_in_pane": 0
                },
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 1
                }
              ]
            }
          ]
        },
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
1
b
OUT
  exit 0
fi
exit 0
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" list 2>&1 || true)"
  assert_contains "Workspace  Session" "$output" "expected list header row"
  assert_contains "1  a    Alpha      backend" "$output" "expected first row without title or conflict marker"
  assert_contains "2  b    Beta       api-1" "$output" "expected second row without title or conflict marker"
  case "$output" in
    *"Title"*|*"Join a session with"*|*"Tip: use mux"*|*"(*)"*)
      fail "expected mux list to omit deprecated title, conflict, and helper text"
      ;;
  esac
  case "$output" in
    *lazygit*)
      fail "expected mux list to exclude non-mux terminals"
      ;;
  esac
}

test_mux_list_sanitizes_control_characters_in_session_names() {
  local temp_dir stub_dir output esc
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  esc="$(printf '\033')"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{"windows":[]}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "list-sessions" ] && [ "$2" = "-F" ]; then
  printf 'plain\n'
  printf 'evil\033[31mred\033[0m\n'
  exit 0
fi
exit 0
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" list 2>&1 || true)"

  assert_contains "plain" "$output" "expected mux list to keep normal unmanaged session names"
  assert_contains "evil?[31mred?[0m" "$output" "expected mux list to replace control characters in session names"
  case "$output" in
    *"$esc"*)
      fail "expected mux list output to avoid raw escape bytes"
      ;;
  esac
}

test_mux_list_hides_conflict_marker_when_no_selector_conflicts_exist() {
  local temp_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
api-1
OUT
  exit 0
fi
exit 0
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" list 2>&1 || true)"
  case "$output" in
    *"Title"*|*"Join a session with"*|*"Tip: use mux"*|*"(*)"*)
      fail "expected mux list to omit deprecated title, conflict, and helper text"
      ;;
  esac
}

test_mux_list_ignores_transient_command_titles_that_are_not_tmux_sessions() {
  local temp_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "caller": {
    "surface_ref": "surface:transient"
  },
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "ref": "surface:backend",
                  "index_in_pane": 0
                },
                {
                  "type": "terminal",
                  "title": "mux list 456",
                  "ref": "surface:transient",
                  "index_in_pane": 1
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "list-sessions" ] && [ "$2" = "-F" ]; then
  cat <<'OUT'
backend
OUT
  exit 0
fi
exit 0
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" list 2>&1 || true)"
  assert_contains "1  a    Alpha      backend" "$output" "expected the real mux session to stay listed"
  case "$output" in
    *"Alpha      list 456"*|*"2  b"*)
      fail "expected transient command-title surfaces like mux list to be excluded from mux list"
      ;;
  esac
}

test_mux_list_appends_unmanaged_tmux_sessions_after_mux_entries() {
  local temp_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
api-1
ops
stray
OUT
  exit 0
fi
exit 0
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" list 2>&1 || true)"
  assert_contains "1  a    Alpha      backend" "$output" "expected managed backend row to stay first"
  assert_contains "2  b    Beta       api-1" "$output" "expected managed api row to stay second"
  assert_contains "3  c    -          ops" "$output" "expected first unmanaged tmux session to be appended"
  assert_contains "4  d    -          stray" "$output" "expected second unmanaged tmux session to be appended"
}

test_mux_numeric_selection_is_invalid() {
  local temp_dir stub_dir log_file output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  output="$(PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" 1 2>&1 || true)"

  assert_contains "usage: mux" "$output" "expected mux 1 to print usage"
  if [ -f "$log_file" ]; then
    case "$(cat "$log_file")" in
      *"tmux:new-session -A -s"*)
        fail "expected mux 1 to avoid tmux launch"
        ;;
    esac
  fi
}

test_mux_letter_selection_is_invalid() {
  local temp_dir stub_dir log_file output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  output="$(PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" b 2>&1 || true)"

  assert_contains "usage: mux" "$output" "expected mux b to print usage"
  if [ -f "$log_file" ]; then
    case "$(cat "$log_file")" in
      *"tmux:new-session -A -s"*)
        fail "expected mux b to avoid tmux launch"
        ;;
    esac
  fi
}

test_mux_join_numeric_selector_attaches_by_list_index() {
  local temp_dir stub_dir log_file
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" join 1 || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s backend" "$(cat "$log_file")" "expected mux join 1 to attach to the first listed session"
}

test_mux_join_alias_letter_selector_attaches_by_list_key() {
  local temp_dir stub_dir log_file
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" j b || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s api-1" "$(cat "$log_file")" "expected mux j b to attach to the second listed session"
}

test_mux_join_selector_attaches_to_appended_unmanaged_tmux_session() {
  local temp_dir stub_dir log_file
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
ops
OUT
  exit 0
fi
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" join b || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s ops" "$(cat "$log_file")" "expected mux join b to attach to the appended unmanaged tmux session"
}

test_mux_join_unknown_selector_does_not_fall_back_to_literal_session() {
  local temp_dir stub_dir log_file output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{"windows":[]}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" join 999 2>&1 || true)"

  assert_contains "unknown mux selector: 999" "$output" "expected mux join 999 to reject unknown selectors"
  if [ -f "$log_file" ]; then
    case "$(cat "$log_file")" in
      *"tmux:new-session -A -s 999"*)
        fail "expected mux join 999 to avoid literal session fallback"
        ;;
    esac
  fi
}

test_mux_join_without_selector_reads_prompt_in_interactive_mode() {
  local temp_dir stub_dir log_file output run_script expect_script
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  output="$temp_dir/output.txt"
  run_script="$temp_dir/run-join.sh"
  expect_script="$temp_dir/run-join.expect"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$run_script" <<EOF
#!/usr/bin/env bash
PATH="$stub_dir:\$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" join
EOF

  cat >"$expect_script" <<EOF
log_file -noappend "$output"
spawn "$run_script"
expect "selector: "
send "b\r"
expect eof
EOF

  expect "$expect_script" >/dev/null 2>&1 || true

  assert_file_exists "$log_file"
  assert_contains "Workspace" "$(cat "$output")" "expected mux join to print the list before prompting"
  assert_contains "selector:" "$(cat "$output")" "expected mux join to prompt for a selector in interactive mode"
  assert_contains "tmux:new-session -A -s api-1" "$(cat "$log_file")" "expected mux join to attach after reading the prompt selection"
}

test_mux_join_without_selector_prints_list_and_errors_in_non_interactive_mode() {
  local temp_dir stub_dir log_file output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  output="$temp_dir/output.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" join >"$output" 2>&1 || true

  assert_contains "Workspace" "$(cat "$output")" "expected mux join to print the list in non-interactive mode"
  assert_contains "selector required in non-interactive mode" "$(cat "$output")" "expected mux join to fail instead of hanging without a tty"
  if [ -f "$log_file" ]; then
    case "$(cat "$log_file")" in
      *"tmux:new-session -A -s"*)
        fail "expected mux join with no selector in non-interactive mode to avoid tmux launch"
        ;;
    esac
  fi
}

test_mux_invalid_numeric_selection_does_not_launch_tmux_from_list_stdin() {
  local temp_dir stub_dir log_file
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux api-1",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
printf 'cmux:%s\n' "\$*" >>"$log_file"
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
if IFS= read -r line; then
  printf 'stdin:%s\n' "\$line" >>"$log_file"
fi
EOF

  PATH="$stub_dir:$PATH" \
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" 1 >"$temp_dir/output.txt" 2>&1 || true

  if [ -f "$log_file" ]; then
    case "$(cat "$log_file")" in
      *"stdin:"*|*"tmux:new-session -A -s"*)
        fail "expected mux 1 to avoid tmux launch entirely"
        ;;
    esac
  fi
  assert_contains "usage: mux" "$(cat "$temp_dir/output.txt")" "expected mux 1 to print usage"
}

test_mux_unknown_selectors_error_without_launching_sessions() {
  local temp_dir stub_dir output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{"windows":[]}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
exit 1
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" 999 2>&1 || true)"
  assert_contains "usage: mux" "$output" "expected mux 999 to print usage when no selector matches"

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" z 2>&1 || true)"
  assert_contains "usage: mux" "$output" "expected mux z to print usage when no selector matches"
}

test_mux_list_and_invalid_selector_work_without_cmux_using_saved_state() {
  local temp_dir stub_dir state_file log_file output jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  state_file="$temp_dir/state.json"
  log_file="$temp_dir/log.txt"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$state_file" <<'EOF'
{
  "version": 1,
  "workspaces": [
    {
      "title": "Alpha",
      "entries": [
        {
          "title": "mux backend",
          "session": "backend",
          "pane_index": 0,
          "surface_index_in_pane": 0
        }
      ]
    },
    {
      "title": "Beta",
      "entries": [
        {
          "title": "mux api-1",
          "session": "api-1",
          "pane_index": 0,
          "surface_index_in_pane": 1
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
1
b
OUT
  exit 0
fi
printf 'tmux:%s\n' "\$*" >>"$log_file"
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  output="$(PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" list 2>&1 || true)"
  assert_contains "Workspace  Session" "$output" "expected saved-state list header without cmux"
  assert_contains "1  a    Alpha      backend" "$output" "expected saved-state first row without title or conflict marker"
  assert_contains "2  b    Beta       api-1" "$output" "expected saved-state ordering without cmux"
  case "$output" in
    *"Title"*|*"Join a session with"*|*"Tip: use mux"*|*"(*)"*)
      fail "expected saved-state list to omit deprecated title, conflict, and helper text"
      ;;
  esac

  output="$(PATH="$stub_dir:/usr/bin:/bin" \
  MUX_STATE_FILE="$state_file" \
  "$ROOT_DIR/bin/mux" 1 2>&1 || true)"

  assert_contains "usage: mux" "$output" "expected numeric selection to print usage from saved state without cmux"
  if [ -f "$log_file" ]; then
    case "$(cat "$log_file")" in
      *"tmux:new-session -A -s"*)
        fail "expected saved-state numeric selection to avoid tmux launch"
        ;;
    esac
  fi
}

test_mux_list_falls_back_to_saved_state_when_cmux_tree_fails() {
  local temp_dir stub_dir state_file output jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  state_file="$temp_dir/state.json"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$state_file" <<'EOF'
{
  "version": 1,
  "workspaces": [
    {
      "title": "Alpha",
      "entries": [
        {
          "title": "mux backend",
          "session": "backend",
          "pane_index": 0,
          "surface_index_in_pane": 0
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tree" ] && [ "$2" = "--all" ] && [ "$3" = "--json" ]; then
  echo "Error: Failed to write to socket" >&2
  exit 1
fi
exit 0
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  write_executable "$stub_dir/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "list-sessions" ] && [ "$2" = "-F" ]; then
  exit 0
fi
exit 0
EOF

  output="$(PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" list 2>&1 || true)"

  assert_contains "1  a    Alpha      backend" "$output" "expected mux list to fall back to saved state when cmux tree fails"
  case "$output" in
    *"Failed to write to socket"*)
      fail "expected mux list to suppress raw cmux socket errors when falling back to saved state"
      ;;
  esac
}

test_save_and_s_rewrite_state_with_only_canonical_mux_tabs() {
  local temp_dir stub_dir state_file tree_json
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  state_file="$temp_dir/state.json"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "ref": "workspace:1",
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "ref": "surface:10",
                  "pane_ref": "pane:1",
                  "type": "terminal",
                  "title": "mux claude-123",
                  "index_in_pane": 0
                }
              ]
            },
            {
              "index": 1,
              "surfaces": [
                {
                  "ref": "surface:11",
                  "pane_ref": "pane:2",
                  "type": "terminal",
                  "title": "mux tab legacy",
                  "index_in_pane": 0
                },
                {
                  "ref": "surface:12",
                  "pane_ref": "pane:2",
                  "type": "terminal",
                  "title": "lazygit",
                  "index_in_pane": 1
                }
              ]
            }
          ]
        },
        {
          "ref": "workspace:2",
          "title": "Beta",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "ref": "surface:20",
                  "pane_ref": "pane:3",
                  "type": "browser",
                  "title": "Docs",
                  "index_in_pane": 0
                },
                {
                  "ref": "surface:21",
                  "pane_ref": "pane:3",
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 1
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
echo "unexpected cmux call: \$*" >&2
exit 1
EOF

  printf 'stale\n' >"$state_file"

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$state_file" \
  "$ROOT_DIR/bin/mux" save

  assert_json_filter_equals "$state_file" '.version' "1"
  assert_json_filter_equals "$state_file" '.workspaces | length' "2"
  assert_json_filter_equals "$state_file" '.workspaces[0].title' "Alpha"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries | length' "1"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries[0].session' "claude-123"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries[0].pane_index' "0"
  assert_json_filter_equals "$state_file" '.workspaces[1].entries[0].title' "mux backend"
  assert_json_filter_equals "$state_file" '.workspaces[1].entries[0].session' "backend"

  printf 'stale-again\n' >"$state_file"

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$state_file" \
  "$ROOT_DIR/bin/mux" s

  assert_json_filter_equals "$state_file" '.version' "1"
  assert_json_filter_equals "$state_file" '.workspaces | length' "2"
  assert_json_filter_equals "$state_file" '.workspaces[0].title' "Alpha"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries | length' "1"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries[0].session' "claude-123"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries[0].pane_index' "0"
  assert_json_filter_equals "$state_file" '.workspaces[1].entries[0].title' "mux backend"
  assert_json_filter_equals "$state_file" '.workspaces[1].entries[0].session' "backend"
}

test_mux_save_preserves_existing_state_when_cmux_tree_is_empty() {
  local temp_dir stub_dir state_file output before_contents jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  state_file="$temp_dir/state.json"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$state_file" <<'EOF'
{
  "version": 1,
  "workspaces": [
    {
      "title": "Alpha",
      "entries": [
        {
          "title": "mux backend",
          "session": "backend",
          "pane_index": 0,
          "surface_index_in_pane": 0
        }
      ]
    }
  ]
}
EOF

  before_contents="$(cat "$state_file")"

  write_executable "$stub_dir/cmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tree" ] && [ "$2" = "--all" ] && [ "$3" = "--json" ]; then
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  output="$(PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" save 2>&1 || true)"

  assert_contains "cmux tree unavailable" "$output" "expected mux save to reject empty cmux tree output"
  assert_eq "$before_contents" "$(cat "$state_file")" "expected mux save to preserve the existing state file when cmux tree output is empty"
}

test_mux_restore_rejects_empty_state_file() {
  local temp_dir stub_dir state_file output
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  state_file="$temp_dir/state.json"
  mkdir -p "$stub_dir"
  : >"$state_file"

  write_executable "$stub_dir/cmux" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tree" ] && [ "$2" = "--all" ] && [ "$3" = "--json" ]; then
  printf '{"windows":[]}'
  exit 0
fi
exit 0
EOF

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" restore 2>&1 || true)"

  assert_contains "invalid or empty state file" "$output" "expected mux restore to reject empty snapshots"
  assert_contains "run: mux save" "$output" "expected mux restore to recommend re-saving after an empty snapshot"
}

test_restore_respawns_matching_saved_canonical_mux_tabs_best_effort() {
  local temp_dir stub_dir state_file log_file
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  state_file="$temp_dir/state.json"
  log_file="$temp_dir/log.txt"
  mkdir -p "$stub_dir"

  cat >"$state_file" <<'EOF'
{
  "version": 1,
  "workspaces": [
    {
      "title": "Alpha",
      "entries": [
        {
          "title": "mux claude-123",
          "session": "claude-123",
          "pane_index": 0,
          "surface_index_in_pane": 0
        }
      ]
    },
    {
      "title": "Beta",
      "entries": [
        {
          "title": "mux backend",
          "session": "backend",
          "pane_index": 1,
          "surface_index_in_pane": 0
        }
      ]
    },
    {
      "title": "Missing",
      "entries": [
        {
          "title": "mux ignored",
          "session": "ignored",
          "pane_index": 0,
          "surface_index_in_pane": 0
        }
      ]
    }
  ]
}
EOF

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "ref": "workspace:10",
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "ref": "surface:100",
                  "type": "terminal",
                  "title": "mux claude-123",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        },
        {
          "ref": "workspace:20",
          "title": "Beta",
          "panes": [
            {
              "index": 1,
              "surfaces": [
                {
                  "ref": "surface:200",
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
if [ "\$1" = "respawn-pane" ]; then
  printf 'respawn:%s\n' "\$*" >>"$log_file"
  case "\$*" in
    *"surface:100"*)
      exit 0
      ;;
    *"surface:200"*)
      exit 1
      ;;
  esac
fi
echo "unexpected cmux call: \$*" >&2
exit 1
EOF

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$state_file" \
  "$ROOT_DIR/bin/mux" restore >"$temp_dir/stdout.txt"

  assert_contains "respawn:respawn-pane --workspace workspace:10 --surface surface:100 --command" "$(cat "$log_file")" "expected restore for Alpha"
  assert_contains "respawn:respawn-pane --workspace workspace:20 --surface surface:200 --command" "$(cat "$log_file")" "expected restore attempt for Beta"
  assert_contains "'$ROOT_DIR/bin/mux' tab 'claude-123'" "$(cat "$log_file")" "expected explicit restore command for Alpha"
  assert_contains "'$ROOT_DIR/bin/mux' tab 'backend'" "$(cat "$log_file")" "expected explicit restore command for Beta"
  assert_contains "skipping workspace Missing" "$(cat "$temp_dir/stdout.txt")" "expected missing workspace notice"
}

test_mux_cleanup_requires_cmux() {
  local temp_dir stub_dir output jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  write_executable "$stub_dir/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  output="$(PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" cleanup 2>&1 || true)"
  assert_contains "missing required command: cmux" "$output" "expected mux cleanup to require cmux"
}

test_mux_cleanup_lists_orphans_and_skips_deletion_without_exact_yes() {
  local temp_dir stub_dir output log_file state_file jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  output="$temp_dir/output.txt"
  log_file="$temp_dir/log.txt"
  state_file="$temp_dir/state.json"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
orphan
OUT
  exit 0
fi
if [ "\$1" = "show-environment" ] && [ "\$4" = "MUX_MANAGED" ]; then
  printf 'MUX_MANAGED=1\n'
  exit 0
fi
exit 0
EOF

  printf 'no\n' | PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" cleanup >"$output" 2>&1 || true

  assert_contains "orphan" "$(cat "$output")" "expected mux cleanup to list orphan sessions"
  assert_contains "Type yes to delete these sessions:" "$(cat "$output")" "expected cleanup confirmation prompt"
  case "$(cat "$log_file")" in
    *"kill-session"*)
      fail "expected cleanup to skip deletion when confirmation is not exact yes"
      ;;
  esac
}

test_mux_cleanup_kills_orphans_after_exact_yes() {
  local temp_dir stub_dir output log_file state_file jq_bin log_contents
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  output="$temp_dir/output.txt"
  log_file="$temp_dir/log.txt"
  state_file="$temp_dir/state.json"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
orphan-1
orphan-2
OUT
  exit 0
fi
if [ "\$1" = "show-environment" ] && [ "\$4" = "MUX_MANAGED" ]; then
  printf 'MUX_MANAGED=1\n'
  exit 0
fi
exit 0
EOF

  printf 'yes\n' | PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" cleanup >"$output" 2>&1 || true

  log_contents="$(cat "$log_file")"
  assert_contains "cmux:tree --all --json
cmux:tree --all --json
tmux:list-sessions -F #{session_name}" "$log_contents" "expected cleanup to save before comparing tmux sessions"
  assert_contains "tmux:kill-session -t orphan-1" "$log_contents" "expected cleanup to delete first orphan"
  assert_contains "tmux:kill-session -t orphan-2" "$log_contents" "expected cleanup to delete second orphan"
  case "$log_contents" in
    *"tmux:kill-session -t backend"*)
      fail "expected cleanup to preserve tracked mux sessions"
      ;;
  esac
  assert_json_filter_equals "$state_file" '.workspaces[0].entries[0].session' "backend"
}

test_mux_cleanup_auto_approve_skips_prompt() {
  local temp_dir stub_dir output log_file state_file jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  output="$temp_dir/output.txt"
  log_file="$temp_dir/log.txt"
  state_file="$temp_dir/state.json"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
orphan
OUT
  exit 0
fi
if [ "\$1" = "show-environment" ] && [ "\$4" = "MUX_MANAGED" ]; then
  printf 'MUX_MANAGED=1\n'
  exit 0
fi
exit 0
EOF

  PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" cleanup --auto-approve >"$output" 2>&1 || true

  assert_contains "tmux:kill-session -t orphan" "$(cat "$log_file")" "expected cleanup --auto-approve to delete orphan sessions"
  case "$(cat "$output")" in
    *"Type yes to delete these sessions:"*)
      fail "expected --auto-approve to skip the confirmation prompt"
      ;;
  esac
}

test_mux_cleanup_prints_nothing_to_cleanup_when_all_sessions_are_tracked() {
  local temp_dir stub_dir output log_file state_file jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  output="$temp_dir/output.txt"
  log_file="$temp_dir/log.txt"
  state_file="$temp_dir/state.json"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
OUT
  exit 0
fi
if [ "\$1" = "show-environment" ] && [ "\$4" = "MUX_MANAGED" ]; then
  printf 'MUX_MANAGED=1\n'
  exit 0
fi
exit 0
EOF

  PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" cleanup >"$output" 2>&1 || true

  assert_contains "nothing to cleanup" "$(cat "$output")" "expected cleanup to report no orphan sessions"
  case "$(cat "$log_file")" in
    *"kill-session"*)
      fail "expected cleanup to avoid deletion when no orphan sessions exist"
      ;;
  esac
}

test_mux_cleanup_ignores_sessions_not_created_by_mux() {
  local temp_dir stub_dir output log_file state_file jq_bin
  temp_dir="$(make_temp_dir)"
  stub_dir="$temp_dir/bin"
  output="$temp_dir/output.txt"
  log_file="$temp_dir/log.txt"
  state_file="$temp_dir/state.json"
  jq_bin="$(command -v jq)"
  mkdir -p "$stub_dir"

  cat >"$temp_dir/tree.json" <<'EOF'
{
  "windows": [
    {
      "workspaces": [
        {
          "title": "Alpha",
          "panes": [
            {
              "index": 0,
              "surfaces": [
                {
                  "type": "terminal",
                  "title": "mux backend",
                  "index_in_pane": 0
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
EOF

  write_executable "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
exec "$jq_bin" "\$@"
EOF

  write_executable "$stub_dir/cmux" <<EOF
#!/usr/bin/env bash
printf 'cmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "tree" ] && [ "\$2" = "--all" ] && [ "\$3" = "--json" ]; then
  cat "$temp_dir/tree.json"
  exit 0
fi
exit 0
EOF

  # codex-session is NOT mux-managed (show-environment returns error for it)
  write_executable "$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
printf 'tmux:%s\n' "\$*" >>"$log_file"
if [ "\$1" = "list-sessions" ] && [ "\$2" = "-F" ]; then
  cat <<'OUT'
backend
codex-session
OUT
  exit 0
fi
if [ "\$1" = "show-environment" ] && [ "\$4" = "MUX_MANAGED" ]; then
  if [ "\$3" = "codex-session" ]; then
    exit 1
  fi
  printf 'MUX_MANAGED=1\n'
  exit 0
fi
exit 0
EOF

  PATH="$stub_dir:/usr/bin:/bin" MUX_STATE_FILE="$state_file" "$ROOT_DIR/bin/mux" cleanup --auto-approve >"$output" 2>&1 || true

  assert_contains "nothing to cleanup" "$(cat "$output")" "expected cleanup to ignore non-mux sessions"
  case "$(cat "$log_file")" in
    *"kill-session -t codex-session"*)
      fail "expected cleanup to never kill sessions not created by mux"
      ;;
  esac
}

test_readme_documents_supported_commands() {
  local readme
  readme="$(cat "$ROOT_DIR/README.md")"
  assert_contains "mux help" "$readme" "expected help-first default in README"
  assert_contains "mux h" "$readme" "expected short help alias in README"
  assert_contains "mux --help" "$readme" "expected long help flag in README"
  assert_contains "mux list" "$readme" "expected list command in README"
  assert_contains "mux l" "$readme" "expected list alias in README"
  assert_contains "mux t <name>" "$readme" "expected t usage in README"
  assert_contains "mux tab <name>" "$readme" "expected tab usage in README"
  assert_contains "mux join <selector>" "$readme" "expected join usage in README"
  assert_contains "mux j <selector>" "$readme" "expected join alias usage in README"
  assert_contains "mux init" "$readme" "expected init usage in README"
  assert_contains "mux init claude" "$readme" "expected claude init example in README"
  assert_contains "mux init codex" "$readme" "expected codex init example in README"
  assert_contains "mux uninstall" "$readme" "expected uninstall usage in README"
  assert_contains "--scope project" "$readme" "expected project-scope example in README"
  assert_contains "mux save" "$readme" "expected save usage in README"
  assert_contains "mux s" "$readme" "expected short save usage in README"
  assert_contains "mux cleanup" "$readme" "expected cleanup usage in README"
  assert_contains "mux cleanup --auto-approve" "$readme" "expected cleanup auto-approve usage in README"
  assert_contains "mux restore" "$readme" "expected restore usage in README"
  assert_contains "mux r" "$readme" "expected restore alias usage in README"
  case "$readme" in
    *"is an alias for `mux list`."*)
      fail "expected README to drop bare mux list alias docs"
      ;;
    *"mux <selector>"*|*"joins the matching listed mux tab when a selector match exists"*)
      fail "expected README to drop bare selector join docs"
      ;;
  esac
}

main() {
  test_cli_help_flags_print_usage
  test_mux_with_no_args_prints_usage
  test_mux_l_alias_matches_mux_list
  test_mux_r_alias_matches_mux_restore
  test_mux_init_claude_installs_global_hooks
  test_mux_init_claude_project_scope_installs_project_hooks
  test_mux_init_helper_writes_tmux_notifications_to_tty
  test_mux_uninstall_claude_removes_user_project_and_local_project_hooks
  test_mux_init_codex_installs_global_hooks
  test_mux_uninstall_codex_removes_only_mux_hooks_and_feature_flag
  test_mux_init_codex_rejects_project_scope
  test_mux_init_all_skips_missing_apps
  test_install_claude_sandbox_allows_configured_host_ports
  test_tab_uses_tmux_new_session_and_renames_cmux_tab
  test_t_uses_tmux_new_session_and_renames_cmux_tab
  test_mux_tab_rejects_control_characters_in_session_name
  test_bare_name_requires_explicit_launch_command
  test_mux_t_launch_persists_before_entering_tmux
  test_mux_tab_launch_persists_before_entering_tmux
  test_launch_commands_treat_literal_names_as_session_names
  test_mux_list_prints_numbered_mux_tabs_only
  test_mux_list_sanitizes_control_characters_in_session_names
  test_mux_list_hides_conflict_marker_when_no_selector_conflicts_exist
  test_mux_list_ignores_transient_command_titles_that_are_not_tmux_sessions
  test_mux_list_appends_unmanaged_tmux_sessions_after_mux_entries
  test_mux_numeric_selection_is_invalid
  test_mux_letter_selection_is_invalid
  test_mux_join_numeric_selector_attaches_by_list_index
  test_mux_join_alias_letter_selector_attaches_by_list_key
  test_mux_join_selector_attaches_to_appended_unmanaged_tmux_session
  test_mux_join_unknown_selector_does_not_fall_back_to_literal_session
  test_mux_join_without_selector_reads_prompt_in_interactive_mode
  test_mux_join_without_selector_prints_list_and_errors_in_non_interactive_mode
  test_mux_invalid_numeric_selection_does_not_launch_tmux_from_list_stdin
  test_mux_unknown_selectors_error_without_launching_sessions
  test_mux_list_and_invalid_selector_work_without_cmux_using_saved_state
  test_mux_list_falls_back_to_saved_state_when_cmux_tree_fails
  test_save_and_s_rewrite_state_with_only_canonical_mux_tabs
  test_mux_save_preserves_existing_state_when_cmux_tree_is_empty
  test_mux_restore_rejects_empty_state_file
  test_restore_respawns_matching_saved_canonical_mux_tabs_best_effort
  test_mux_cleanup_requires_cmux
  test_mux_cleanup_lists_orphans_and_skips_deletion_without_exact_yes
  test_mux_cleanup_kills_orphans_after_exact_yes
  test_mux_cleanup_auto_approve_skips_prompt
  test_mux_cleanup_prints_nothing_to_cleanup_when_all_sessions_are_tracked
  test_mux_cleanup_ignores_sessions_not_created_by_mux
  test_readme_documents_supported_commands
  echo "PASS"
}

main "$@"
