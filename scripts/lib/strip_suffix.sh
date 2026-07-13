#!/usr/bin/env bash

strip_suffix() {
  local value=${1-}
  local suffix=${2-}

  if [[ $value == *"$suffix" ]]; then
    value=${value:0:${#value}-${#suffix}}
  fi
  printf '%s\n' "$value"
}
