#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNNER="$ROOT/scripts/qemu_headered_stage2_rejection.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { echo "error: $1" >&2; exit 1; }
bash -n "$RUNNER"
echo "ok: runner syntax"
if "$RUNNER" "$TMP_DIR/missing.gwo" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail "missing-image: expected failure"
fi
grep -F 'file not found:' "$TMP_DIR/err" > /dev/null || fail "missing-image: wrong error"
echo "ok: missing image"
