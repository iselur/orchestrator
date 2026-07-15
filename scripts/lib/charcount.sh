#!/usr/bin/env bash

charcount() {
  local value=${1-}

  printf '%d\n' "${#value}"
}
