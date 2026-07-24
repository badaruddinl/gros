#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_grabi_generated_code.sh"
SOURCE_IMAGE="$ROOT/fixtures/generated-code/abi-call-preserve/expected.gwo"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
CASE_IMAGE=""

pass() {
    pass_count=$((pass_count + 1))
    echo "ok: $1"
}

fail() {
    echo "error: $1" >&2
    exit 1
}

copy_case() {
    local name=$1

    CASE_IMAGE="$TMP_DIR/$name.gwo"
    cp "$SOURCE_IMAGE" "$CASE_IMAGE"
}

hex_offset() {
    local pattern=$1
    local hex prefix

    hex=$(od -An -tx1 -v "$CASE_IMAGE" | tr -d ' \n')
    case "$hex" in
        *"$pattern"*) ;;
        *) fail "baseline image does not contain pattern: $pattern" ;;
    esac
    prefix=${hex%%"$pattern"*}
    printf '%s' "$(( ${#prefix} / 2 ))"
}

write_byte() {
    local offset=$1
    local value=$2

    printf '%b' "\\$(printf '%03o' "$value")" |
        dd of="$CASE_IMAGE" bs=1 seek="$offset" count=1 conv=notrunc status=none
}

mutate_pattern() {
    local pattern=$1
    local relative_offset=$2
    local value=$3

    write_byte "$(( $(hex_offset "$pattern") + relative_offset ))" "$value"
}

expect_failure() {
    local name=$1
    local expected=$2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    if "$VALIDATOR" "$CASE_IMAGE" > "$out" 2> "$err"; then
        fail "$name: expected failure"
    fi
    grep -F "$expected" "$err" > /dev/null || {
        cat "$out" >&2
        cat "$err" >&2
        fail "$name: expected error containing '$expected'"
    }
    pass "$name"
}

[ -f "$SOURCE_IMAGE" ] || fail "missing source fixture: $SOURCE_IMAGE"
bash -n "$VALIDATOR"
pass "validator syntax"

copy_case baseline
"$VALIDATOR" "$CASE_IMAGE" > /dev/null
pass "baseline fixture"

copy_case wrong-size
truncate -s 1024 "$CASE_IMAGE"
expect_failure wrong-size "expected generated ABI fixture must be 2048 bytes"

copy_case missing-entry-contract
mutate_pattern "fcb81111bb2222b93333ba4444687777e8070083c402faf4ebfc" 0 0
expect_failure missing-entry-contract "DF-clear entry, register arguments, stack argument, caller cleanup, and halt"

copy_case missing-callee-contract
mutate_pattern "5589e51e065657beaaaabfbbbb31c08ed88ec08b4604fc071f5f5e5dc3" 0 0
expect_failure missing-callee-contract "callee frame, saved segments/registers, AX stack return, DF clear, and restore sequence"

copy_case grscall-dependency
write_byte 128 205
write_byte 129 48
expect_failure grscall-dependency "generated ABI fixture must not depend on GrSCall"

echo "passed: $pass_count"
