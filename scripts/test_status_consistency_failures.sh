#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_status_consistency.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass() { echo "ok: $1"; }
fail() { echo "error: $1" >&2; exit 1; }

CASE_ROOT="$TMP_DIR/case"
mkdir -p "$CASE_ROOT/scripts"
cp -R "$ROOT/docs" "$CASE_ROOT/docs"
cp "$VALIDATOR" "$CASE_ROOT/scripts/check_status_consistency.sh"

bash -n "$VALIDATOR"
pass "validator syntax"
STATUS_CONSISTENCY_ROOT="$CASE_ROOT" STATUS_CONSISTENCY_SELF_TEST=1 "$VALIDATOR" > /dev/null
pass "baseline"
printf '%s\n' 'Grown .grw is specified but not compiled yet.' >> "$CASE_ROOT/docs/00-naming.md"
if STATUS_CONSISTENCY_ROOT="$CASE_ROOT" STATUS_CONSISTENCY_SELF_TEST=1 "$VALIDATOR" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail "stale-claim: expected failure"
fi
grep -F 'stale status text' "$TMP_DIR/err" > /dev/null || fail "stale-claim: wrong error"
pass "stale claim"
