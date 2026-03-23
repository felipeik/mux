#!/usr/bin/env bash

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-expected '$expected' but got '$actual'}"
  if [ "$expected" != "$actual" ]; then
    fail "$message"
  fi
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local message="${3:-expected output to contain '$needle'}"
  case "$haystack" in
    *"$needle"*) ;;
    *)
      fail "$message"
      ;;
  esac
}

assert_file_exists() {
  local path="$1"
  if [ ! -f "$path" ]; then
    fail "expected file to exist: $path"
  fi
}

assert_json_filter_equals() {
  local path="$1"
  local filter="$2"
  local expected="$3"
  local actual
  actual="$(jq -r "$filter" "$path")"
  if [ "$actual" != "$expected" ]; then
    fail "expected jq filter '$filter' on $path to be '$expected' but got '$actual'"
  fi
}
