#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNNER="$ROOT/scripts/run_validation_lane.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    echo "error: $1" >&2
    exit 1
}

pass() {
    echo "ok: $1"
}

bash -n "$RUNNER"
pass "runner syntax"

if "$RUNNER" success true > "$TMP_DIR/success.out" 2> "$TMP_DIR/success.err"; then
    grep -F "validation lane: success: ok (" "$TMP_DIR/success.out" > /dev/null \
        || fail "success lane missing duration"
else
    fail "success lane unexpectedly failed"
fi
pass "success status"

if "$RUNNER" failure bash -c 'exit 17' > "$TMP_DIR/failure.out" 2> "$TMP_DIR/failure.err"; then
    fail "failure lane unexpectedly passed"
fi
grep -F "validation lane: failure: failed (status=17," "$TMP_DIR/failure.err" > /dev/null \
    || fail "failure lane did not preserve status"
pass "failure status"

if "$RUNNER" missing-command "$TMP_DIR/missing-command" > "$TMP_DIR/missing.out" 2> "$TMP_DIR/missing.err"; then
    fail "missing command unexpectedly passed"
fi
grep -F "validation lane: missing-command: failed (status=" "$TMP_DIR/missing.err" > /dev/null \
    || fail "missing command did not report failure"
pass "missing command"
