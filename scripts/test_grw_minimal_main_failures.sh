#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPILER="$ROOT/scripts/grw_minimal_main.sh"
SOURCE="$ROOT/examples/generated/minimal-main-void.grw"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
pass_count=0

pass() { pass_count=$((pass_count + 1)); echo "ok: $1"; }
fail() { echo "error: $1" >&2; exit 1; }

expect_failure() {
    local name=$1
    local body=$2
    local expected=${3:-'unsupported source'}
    local input="$TMP_DIR/$name.grw"
    local output="$TMP_DIR/$name.gwn"
    printf '%s\n' "$body" > "$input"
    if "$COMPILER" "$input" "$output" > "$TMP_DIR/$name.out" 2> "$TMP_DIR/$name.err"; then
        fail "$name: expected compiler failure"
    fi
    grep -F "$expected" "$TMP_DIR/$name.err" > /dev/null || fail "$name: missing rejection reason"
    pass "$name"
}

bash -n "$COMPILER"
pass "compiler syntax"
"$COMPILER" "$SOURCE" "$TMP_DIR/baseline.gwn" > /dev/null
grep -F 'origin 8020' "$TMP_DIR/baseline.gwn" > /dev/null || fail "baseline: missing payload origin"
pass "baseline subset"

expect_failure "wrong-target" $'target "host.linux.x86_64.v0"\nfn main() -> void { return; }'
expect_failure "missing-return" $'target "gros.x86.bios.real16.stage2.v0"\nfn main() -> void { }'
expect_failure "extra-function" $'target "gros.x86.bios.real16.stage2.v0"\nfn main() -> void { return; }\nfn other() -> void { return; }'
expect_failure "duplicate-target" $'target "gros.x86.bios.real16.stage2.v0"\ntarget "gros.x86.bios.real16.stage2.v0"\nfn main() -> void { return; }'
expect_failure "block-comment" $'target "gros.x86.bios.real16.stage2.v0"\n/* reserved */\nfn main() -> void { return; }' 'block comments are reserved'

printf '%s\r\n' 'target "gros.x86.bios.real16.stage2.v0" // selected profile' '' 'fn main() -> void {' '    // return from the only supported body' '    return;' '}' > "$TMP_DIR/comments-crlf.grw"
"$COMPILER" "$TMP_DIR/comments-crlf.grw" "$TMP_DIR/comments-crlf.gwn" > /dev/null
cmp -s "$TMP_DIR/baseline.gwn" "$TMP_DIR/comments-crlf.gwn" || fail "comments-crlf: output must stay deterministic"
pass "comments and CRLF"

echo "passed: $pass_count"
