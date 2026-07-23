#!/usr/bin/env bash
set -eu

target="${1:-unknown}"
reason="${2:-not implemented in the current milestone}"

printf 'SKIP: %s -- %s\n' "$target" "$reason"
