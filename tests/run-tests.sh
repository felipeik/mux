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
  "$ROOT_DIR/bin/mux" tab claude-123 || true

  assert_file_exists "$log_file"
  assert_contains "cmux:rename-tab --workspace workspace:1 --surface surface:9 mux tab claude-123" "$(cat "$log_file")" "expected cmux tab rename"
  assert_contains "tmux:new-session -A -s claude-123" "$(cat "$log_file")" "expected tmux new-session -A -s"
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
                  "title": "mux tab backend",
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
  assert_json_filter_equals "$state_file" '.workspaces[1].entries[0].title' "mux tab backend"
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
          "title": "mux tab backend",
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
                  "title": "mux tab backend",
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
  assert_contains "skipping workspace Missing" "$(cat "$temp_dir/stdout.txt")" "expected missing workspace notice"
}

test_readme_documents_supported_commands() {
  local readme
  readme="$(cat "$ROOT_DIR/README.md")"
  assert_contains "mux tab <name>" "$readme" "expected tab usage in README"
  assert_contains "mux persist" "$readme" "expected persist usage in README"
  assert_contains "mux restore" "$readme" "expected restore usage in README"
}

main() {
  test_cli_help_requires_script
  test_tab_uses_tmux_new_session_and_renames_cmux_tab
  test_persist_rewrites_state_with_only_mux_tabs
  test_restore_respawns_matching_saved_mux_tabs_best_effort
  test_readme_documents_supported_commands
  echo "PASS"
}

main "$@"
