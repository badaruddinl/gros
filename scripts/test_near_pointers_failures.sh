#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_near_pointers.sh"
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

stage2_hex() {
    dd if="$1" bs=512 skip=1 count=4 2> /dev/null |
        od -An -tx1 -v |
        tr -d ' \n'
}

stage2_pattern_offset() {
    local image=$1
    local pattern=$2
    local hex prefix

    hex=$(stage2_hex "$image")
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

mutate_stage2_pattern_byte() {
    local pattern=$1
    local relative_offset=$2
    local value=$3
    local stage2_offset absolute_offset

    stage2_offset=$(stage2_pattern_offset "$CASE_IMAGE" "$pattern")
    absolute_offset=$((512 + stage2_offset + relative_offset))
    write_byte "$absolute_offset" "$value"
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
        missing-int30-vector)
            mutate_stage2_pattern_byte "c706c000c580c706c2000000" 0 0
            ;;
        int30-handler-before-stage2)
            mutate_stage2_pattern_byte "c706c000c580c706c2000000" 5 127
            ;;
        int30-handler-past-stage2)
            mutate_stage2_pattern_byte "c706c000c580c706c2000000" 5 136
            ;;
        too-few-si-write-loads)
            mutate_stage2_pattern_byte "be5081e89b00" 0 0
            mutate_stage2_pattern_byte "be5c81e89500" 0 0
            ;;
        si-write-past-stage2)
            mutate_stage2_pattern_byte "be5081e89b00" 2 136
            ;;
        too-few-compare-pairs)
            mutate_stage2_pattern_byte "bea681bf6c81e8b100" 0 0
            ;;
        di-compare-past-stage2)
            mutate_stage2_pattern_byte "bea681bf6c81e8b100" 5 136
            ;;
        missing-input-buffer-pointer)
            mutate_stage2_pattern_byte "bfa68131c9" 0 0
            ;;
        input-buffer-past-stage2)
            mutate_stage2_pattern_byte "bfa68131c9" 2 136
            ;;
        missing-write-string-forward)
            mutate_stage2_pattern_byte "b80001cd30c3" 0 0
            ;;
        missing-si-preservation-fixture)
            mutate_stage2_pattern_byte "56fce8" 0 0
            ;;
        *)
            fail "unknown near-pointer negative test: $name"
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

expect_validator_failure "wrong-size" "stage-2 boot image must be 2560 bytes"
expect_validator_failure "empty-stage2-payload" "stage-2 payload must not be empty"
expect_validator_failure "missing-int30-vector" "missing int 30h vector install fixture"
expect_validator_failure "int30-handler-before-stage2" "int 30h handler points before stage-2"
expect_validator_failure "int30-handler-past-stage2" "int 30h handler points past stage-2"
expect_validator_failure "too-few-si-write-loads" "expected at least 6 SI write pointer loads"
expect_validator_failure "si-write-past-stage2" "SI write immediate points past stage-2"
expect_validator_failure "too-few-compare-pairs" "expected 4 SI/DI compare pointer pairs"
expect_validator_failure "di-compare-past-stage2" "DI compare immediate points past stage-2"
expect_validator_failure "missing-input-buffer-pointer" "expected one DI input buffer pointer load, got 0"
expect_validator_failure "input-buffer-past-stage2" "DI input buffer immediate points past stage-2"
expect_validator_failure "missing-write-string-forward" "missing near-pointer byte fixture: write_string forwards DS:SI to console/text.write_cstr"
expect_validator_failure "missing-si-preservation-fixture" "missing near-pointer byte fixture: console/text.write_cstr preserves SI before local string walk"

echo "passed: $pass_count"
