#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib/strip_suffix.sh

assert_strip_suffix() {
  local input=$1
  local suffix=$2
  local expected=$3
  local actual

  actual=$(strip_suffix "$input" "$suffix")
  if [[ $actual != "$expected" ]]; then
    printf 'strip_suffix %q %q: expected %q, got %q\n' \
      "$input" "$suffix" "$expected" "$actual" >&2
    return 1
  fi
}

assert_strip_suffix 'file.txt' '.txt' 'file'
assert_strip_suffix 'file.txt' '.md' 'file.txt'
