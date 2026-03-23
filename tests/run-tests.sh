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

test_cli_help_requires_script() {
  local output
  output="$("$ROOT_DIR/bin/mux" 2>&1 || true)"
  assert_contains "usage" "$output" "expected mux help output"
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
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux tab claude-123" "$(cat "$log_file")" "expected cmux tab rename"
  assert_contains "tmux:new-session -A -s claude-123" "$(cat "$log_file")" "expected tmux new-session -A -s"
}

test_bare_name_uses_tmux_new_session_and_renames_cmux_tab() {
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
  "$ROOT_DIR/bin/mux" claude-123 || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux claude-123" "$(cat "$log_file")" "expected cmux tab rename for bare alias"
  assert_contains "tmux:new-session -A -s claude-123" "$(cat "$log_file")" "expected tmux new-session -A -s for bare alias"
}

test_mux_launch_persists_before_entering_tmux() {
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
  "$ROOT_DIR/bin/mux" backend || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux backend" "$(cat "$log_file")" "expected tab rename before launch"
  assert_contains "cmux:tree --all --json" "$(cat "$log_file")" "expected persist tree snapshot before tmux launch"
  assert_contains "tmux:new-session -A -s backend" "$(cat "$log_file")" "expected tmux new-session for bare launch"
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
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux tab backend" "$(cat "$log_file")" "expected tab rename before legacy launch"
  assert_contains "cmux:tree --all --json" "$(cat "$log_file")" "expected persist tree snapshot before legacy tmux launch"
  assert_contains "tmux:new-session -A -s backend" "$(cat "$log_file")" "expected tmux new-session for legacy launch"
}

test_exact_integer_tab_names_still_launch() {
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

  output="$(PATH="$stub_dir:$PATH" MUX_STATE_FILE="$temp_dir/state.json" "$ROOT_DIR/bin/mux" tab 1 2>&1 || true)"
  case "$output" in
    *"integer"*)
      fail "expected mux tab 1 to be treated as a valid session name"
      ;;
  esac
  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab" "$(cat "$log_file")" "expected mux tab 1 to rename the tab"
  assert_contains "tmux:new-session -A -s 1" "$(cat "$log_file")" "expected mux tab 1 to launch session 1"
}

test_non_integer_names_still_launch() {
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
  "$ROOT_DIR/bin/mux" api-1 || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux api-1" "$(cat "$log_file")" "expected non-integer session rename"
  assert_contains "tmux:new-session -A -s api-1" "$(cat "$log_file")" "expected non-integer session launch"
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
  assert_contains "Join a session with: mux 1 or mux a" "$output" "expected top list helper"
  assert_contains "Workspace  Title        Session" "$output" "expected list header row"
  assert_contains "1(*)  a     Alpha      mux backend  backend" "$output" "expected integer conflict marker on first row"
  assert_contains "2     b(*)  Beta       mux api-1    api-1" "$output" "expected letter conflict marker on second row"
  assert_contains "(*) selector conflicts with an existing tmux session name" "$output" "expected conflict hint"
  assert_contains "Tip: use mux 1 or mux a to join a listed session" "$output" "expected bottom list helper"
  case "$output" in
    *lazygit*)
      fail "expected mux list to exclude non-mux terminals"
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
    *"(*) selector conflicts with an existing tmux session name"*|*"(*)"*)
      fail "expected mux list to omit conflict markers when selectors do not collide"
      ;;
  esac
}

test_mux_numeric_selection_attaches_by_list_index() {
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
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" 1 || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s backend" "$(cat "$log_file")" "expected mux 1 to attach to the first listed session"
}

test_mux_letter_selection_attaches_by_list_key() {
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
  CMUX_WORKSPACE_ID="workspace:1" \
  CMUX_SURFACE_ID="surface:9" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" b || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s api-1" "$(cat "$log_file")" "expected mux b to attach to the second listed session"
}

test_mux_numeric_selection_does_not_launch_tmux_from_list_stdin() {
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
  "$ROOT_DIR/bin/mux" 1 || true

  assert_file_exists "$log_file"
  case "$(cat "$log_file")" in
    *"stdin:"*)
      fail "expected mux 1 to launch tmux after list iteration, not with list stdin attached"
      ;;
  esac
}

test_mux_numeric_selection_rejects_unknown_index() {
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
  case "$output" in
    *"unknown mux list index"*)
      fail "expected mux 999 to fall back to a literal session name when no list match exists"
      ;;
  esac
}

test_mux_unmatched_numeric_and_letter_fall_back_to_session_names() {
  local temp_dir stub_dir log_file
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

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" 999 || true

  PATH="$stub_dir:$PATH" \
  MUX_STATE_FILE="$temp_dir/state.json" \
  "$ROOT_DIR/bin/mux" z || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s 999" "$(cat "$log_file")" "expected unmatched numeric token to remain a literal session name"
  assert_contains "tmux:new-session -A -s z" "$(cat "$log_file")" "expected unmatched letter token to remain a literal session name"
}

test_mux_list_and_index_work_without_cmux_using_saved_state() {
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
  assert_contains "Join a session with: mux 1 or mux a" "$output" "expected saved-state top helper without cmux"
  assert_contains "Workspace  Title        Session" "$output" "expected saved-state list header without cmux"
  assert_contains "1(*)  a     Alpha      mux backend  backend" "$output" "expected saved-state list output without cmux"
  assert_contains "2     b(*)  Beta       mux api-1    api-1" "$output" "expected saved-state ordering without cmux"
  assert_contains "(*) selector conflicts with an existing tmux session name" "$output" "expected saved-state conflict hint without cmux"
  assert_contains "Tip: use mux 1 or mux a to join a listed session" "$output" "expected saved-state bottom helper without cmux"

  PATH="$stub_dir:/usr/bin:/bin" \
  MUX_STATE_FILE="$state_file" \
  "$ROOT_DIR/bin/mux" 1 || true

  assert_file_exists "$log_file"
  assert_contains "tmux:new-session -A -s backend" "$(cat "$log_file")" "expected numeric selection to work from saved state without cmux"
}

test_persist_rewrites_state_with_only_mux_tabs() {
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
                  "title": "mux tab claude-123",
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
                  "title": "lazygit",
                  "index_in_pane": 0
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
  "$ROOT_DIR/bin/mux" persist

  assert_json_filter_equals "$state_file" '.version' "1"
  assert_json_filter_equals "$state_file" '.workspaces | length' "2"
  assert_json_filter_equals "$state_file" '.workspaces[0].title' "Alpha"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries | length' "1"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries[0].session' "claude-123"
  assert_json_filter_equals "$state_file" '.workspaces[0].entries[0].pane_index' "0"
  assert_json_filter_equals "$state_file" '.workspaces[1].entries[0].title' "mux backend"
  assert_json_filter_equals "$state_file" '.workspaces[1].entries[0].session' "backend"
}

test_restore_respawns_matching_saved_mux_tabs_best_effort() {
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
          "title": "mux tab claude-123",
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
          "title": "mux tab ignored",
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
                  "title": "mux tab claude-123",
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
  assert_contains "'$ROOT_DIR/bin/mux' tab 'claude-123'" "$(cat "$log_file")" "expected legacy restore command"
  assert_contains "'$ROOT_DIR/bin/mux' 'backend'" "$(cat "$log_file")" "expected alias restore command"
  assert_contains "skipping workspace Missing" "$(cat "$temp_dir/stdout.txt")" "expected missing workspace notice"
}

test_readme_documents_supported_commands() {
  local readme
  readme="$(cat "$ROOT_DIR/README.md")"
  assert_contains "mux <name>" "$readme" "expected bare alias usage in README"
  assert_contains "mux tab <name>" "$readme" "expected tab usage in README"
  assert_contains "mux persist" "$readme" "expected persist usage in README"
  assert_contains "mux restore" "$readme" "expected restore usage in README"
}

main() {
  test_cli_help_requires_script
  test_tab_uses_tmux_new_session_and_renames_cmux_tab
  test_bare_name_uses_tmux_new_session_and_renames_cmux_tab
  test_mux_launch_persists_before_entering_tmux
  test_mux_tab_launch_persists_before_entering_tmux
  test_exact_integer_tab_names_still_launch
  test_non_integer_names_still_launch
  test_mux_list_prints_numbered_mux_tabs_only
  test_mux_list_hides_conflict_marker_when_no_selector_conflicts_exist
  test_mux_numeric_selection_attaches_by_list_index
  test_mux_letter_selection_attaches_by_list_key
  test_mux_numeric_selection_does_not_launch_tmux_from_list_stdin
  test_mux_numeric_selection_rejects_unknown_index
  test_mux_unmatched_numeric_and_letter_fall_back_to_session_names
  test_mux_list_and_index_work_without_cmux_using_saved_state
  test_persist_rewrites_state_with_only_mux_tabs
  test_restore_respawns_matching_saved_mux_tabs_best_effort
  test_readme_documents_supported_commands
  echo "PASS"
}

main "$@"
