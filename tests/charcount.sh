#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib/charcount.sh

assert_charcount() {
  local input=$1
  local expected=$2
  local actual

  actual=$(charcount "$input")
  if [[ $actual != "$expected" ]]; then
    printf 'charcount %q: expected %q, got %q\n' \
      "$input" "$expected" "$actual" >&2
    return 1
  fi
}

assert_charcount 'abc' '3'
assert_charcount '' '0'
assert_charcount 'a b' '3'
