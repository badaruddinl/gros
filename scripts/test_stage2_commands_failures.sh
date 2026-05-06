#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_stage2_commands.sh"
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
        missing-help-data)
            mutate_image_pattern_byte "68656c7000" 0 0
            ;;
        missing-help-compare)
            mutate_image_pattern_byte "be6481bf2a81" 0 0
            ;;
        missing-ver-compare)
            mutate_image_pattern_byte "be6481bf2f81" 0 0
            ;;
        missing-cls-compare)
            mutate_image_pattern_byte "be6481bf3381" 0 0
            ;;
        missing-reboot-compare)
            mutate_image_pattern_byte "be6481bf3781" 0 0
            ;;
        missing-unknown-fallback)
            mutate_image_pattern_byte "be6081e82200e983ff" 0 0
            ;;
        missing-help-action)
            mutate_image_pattern_byte "be3e81e81900e97aff" 0 0
            ;;
        missing-ver-action)
            mutate_image_pattern_byte "be5481e81000e971ff" 0 0
            ;;
        missing-cls-action)
            mutate_image_pattern_byte "b80300cd10e969ff" 0 0
            ;;
        missing-reboot-action)
            mutate_image_pattern_byte "cd19e964ff" 0 0
            ;;
        missing-string-equal-convention)
            mutate_image_pattern_byte "acae750684c075f8f9c3f8c3" 0 0
            ;;
        *)
            fail "unknown stage-2 command negative test: $name"
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
expect_validator_failure "missing-help-data" "missing stage-2 command data fixture:"
expect_validator_failure "missing-help-compare" "missing stage-2 command dispatch fixture: help command compare"
expect_validator_failure "missing-ver-compare" "missing stage-2 command dispatch fixture: ver command compare"
expect_validator_failure "missing-cls-compare" "missing stage-2 command dispatch fixture: cls command compare"
expect_validator_failure "missing-reboot-compare" "missing stage-2 command dispatch fixture: reboot command compare"
expect_validator_failure "missing-unknown-fallback" "missing stage-2 command dispatch fixture: unknown command fallback"
expect_validator_failure "missing-help-action" "missing stage-2 command dispatch fixture: help command action"
expect_validator_failure "missing-ver-action" "missing stage-2 command dispatch fixture: ver command action"
expect_validator_failure "missing-cls-action" "missing stage-2 command dispatch fixture: cls command action"
expect_validator_failure "missing-reboot-action" "missing stage-2 command dispatch fixture: reboot command action"
expect_validator_failure "missing-string-equal-convention" "missing stage-2 command dispatch fixture: string_equal carry convention"

echo "passed: $pass_count"
