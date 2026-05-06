#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_stage2_input.sh"
SOURCE_IMAGE="$ROOT/dist/gros-stage2.gwo"
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

copy_image_case() {
    local name=$1
    local case_root="$TMP_DIR/$name"

    mkdir -p "$case_root"
    CASE_IMAGE="$case_root/gros-stage2.gwo"
    cp "$SOURCE_IMAGE" "$CASE_IMAGE"
}

image_hex() {
    od -An -tx1 -v "$1" | tr -d ' \n'
}

image_pattern_offset() {
    local image=$1
    local pattern=$2
    local hex prefix

    hex=$(image_hex "$image")
    case "$hex" in
        *"$pattern"*) ;;
        *) fail "baseline image does not contain pattern: $pattern" ;;
    esac

    prefix=${hex%%"$pattern"*}
    printf '%s' "$((${#prefix} / 2))"
}

write_byte() {
    local offset=$1
    local value=$2

    printf '%b' "\\$(printf '%03o' "$value")" |
        dd of="$CASE_IMAGE" bs=1 seek="$offset" count=1 conv=notrunc status=none
}

mutate_image_pattern_byte() {
    local pattern=$1
    local relative_offset=$2
    local value=$3
    local offset

    offset=$(image_pattern_offset "$CASE_IMAGE" "$pattern")
    write_byte "$((offset + relative_offset))" "$value"
}

expect_validator_failure() {
    local name=$1
    local expected=$2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    copy_image_case "$name"

    case "$name" in
        wrong-size)
            truncate -s 2559 "$CASE_IMAGE"
            ;;
        empty-stage2-payload)
            dd if=/dev/zero of="$CASE_IMAGE" bs=1 seek=512 count=2048 conv=notrunc status=none
            ;;
        missing-prompt-reset)
            mutate_image_pattern_byte "be2981e89500bf738131c9" 0 0
            ;;
        missing-keyboard-read)
            mutate_image_pattern_byte "31c0cd16" 0 0
            ;;
        missing-enter-branch)
            mutate_image_pattern_byte "3c0d7427" 0 0
            ;;
        missing-backspace-branch)
            mutate_image_pattern_byte "3c087414" 0 0
            ;;
        missing-control-reject)
            mutate_image_pattern_byte "3c2072f0" 0 0
            ;;
        missing-length-guard)
            mutate_image_pattern_byte "83f90f73eb" 0 0
            ;;
        missing-store-echo)
            mutate_image_pattern_byte "88c3aa41b80101cd30" 0 0
            ;;
        missing-backspace-edit)
            mutate_image_pattern_byte "83f90074db4f49be3581e86300ebd1" 0 0
            ;;
        missing-enter-termination)
            mutate_image_pattern_byte "b000aab80201cd3083f90074" 0 0
            ;;
        missing-backspace-data)
            mutate_image_pattern_byte "08200800" 0 0
            ;;
        *)
            fail "unknown stage-2 input negative test: $name"
            ;;
    esac

    if "$VALIDATOR" "$CASE_IMAGE" > "$out" 2> "$err"; then
        fail "$name: expected validator failure"
    fi

    grep -F "$expected" "$err" > /dev/null || {
        echo "stdout:" >&2
        cat "$out" >&2
        echo "stderr:" >&2
        cat "$err" >&2
        fail "$name: expected error containing '$expected'"
    }

    pass "$name"
}

[ -f "$SOURCE_IMAGE" ] || fail "missing source stage-2 image: $SOURCE_IMAGE"

bash -n "$VALIDATOR"
pass "validator syntax"

copy_image_case "baseline"
"$VALIDATOR" "$CASE_IMAGE" > /dev/null
pass "baseline image"

expect_validator_failure "wrong-size" "stage-2 image must be 2560 bytes"
expect_validator_failure "empty-stage2-payload" "stage-2 payload must not be empty"
expect_validator_failure "missing-prompt-reset" "missing stage-2 input loop fixture: prompt and input buffer reset"
expect_validator_failure "missing-keyboard-read" "missing stage-2 input loop fixture: keyboard read"
expect_validator_failure "missing-enter-branch" "missing stage-2 input loop fixture: enter branch"
expect_validator_failure "missing-backspace-branch" "missing stage-2 input loop fixture: backspace branch"
expect_validator_failure "missing-control-reject" "missing stage-2 input loop fixture: control character reject"
expect_validator_failure "missing-length-guard" "missing stage-2 input loop fixture: max input length guard"
expect_validator_failure "missing-store-echo" "missing stage-2 input loop fixture: store and runtime echo"
expect_validator_failure "missing-backspace-edit" "missing stage-2 input loop fixture: backspace edit path"
expect_validator_failure "missing-enter-termination" "missing stage-2 input loop fixture: enter terminates line through AX=0102h CRLF service"
expect_validator_failure "missing-backspace-data" "missing stage-2 input data fixture:"

echo "passed: $pass_count"
