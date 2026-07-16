#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
python3 tests/lease_cases.py
