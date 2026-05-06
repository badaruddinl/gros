#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_stage2_data.sh"
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

mutate_stage2_pattern_once() {
    local pattern=$1
    local stage2_offset absolute_offset

    stage2_offset=$(stage2_pattern_offset "$CASE_IMAGE" "$pattern")
    absolute_offset=$((512 + stage2_offset))
    write_byte "$absolute_offset" 0
}

mutate_all_stage2_patterns() {
    local pattern=$1
    local hex

    while :; do
        hex=$(stage2_hex "$CASE_IMAGE")
        case "$hex" in
            *"$pattern"*) mutate_stage2_pattern_once "$pattern" ;;
            *) break ;;
        esac
    done
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
        missing-banner-version)
            mutate_all_stage2_patterns "47724f532076302e350d0a00"
            ;;
        missing-prompt)
            mutate_all_stage2_patterns "67726f756e643e2000"
            ;;
        missing-newline)
            mutate_all_stage2_patterns "0d0a00"
            ;;
        missing-backspace)
            mutate_all_stage2_patterns "08200800"
            ;;
        missing-help-command)
            mutate_all_stage2_patterns "68656c7000"
            ;;
        missing-ver-command)
            mutate_all_stage2_patterns "76657200"
            ;;
        missing-cls-command)
            mutate_all_stage2_patterns "636c7300"
            ;;
        missing-reboot-command)
            mutate_all_stage2_patterns "7265626f6f7400"
            ;;
        missing-help-output)
            mutate_all_stage2_patterns "68656c702076657220636c73207265626f6f740d0a00"
            ;;
        missing-unknown-output)
            mutate_all_stage2_patterns "3f0d0a00"
            ;;
        nonzero-command-buffer-tail)
            write_byte 2559 1
            ;;
        *)
            fail "unknown stage-2 data negative test: $name"
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
expect_validator_failure "missing-banner-version" "missing stage-2 data fixture: banner and version text"
expect_validator_failure "missing-prompt" "missing stage-2 data fixture: prompt text"
expect_validator_failure "missing-newline" "missing stage-2 data fixture: newline text"
expect_validator_failure "missing-backspace" "missing stage-2 data fixture: backspace text"
expect_validator_failure "missing-help-command" "missing stage-2 data fixture: help command"
expect_validator_failure "missing-ver-command" "missing stage-2 data fixture: ver command"
expect_validator_failure "missing-cls-command" "missing stage-2 data fixture: cls command"
expect_validator_failure "missing-reboot-command" "missing stage-2 data fixture: reboot command"
expect_validator_failure "missing-help-output" "missing stage-2 data fixture: help output"
expect_validator_failure "missing-unknown-output" "missing stage-2 data fixture: unknown command output"
expect_validator_failure "nonzero-command-buffer-tail" "stage-2 command buffer tail must remain zero-filled"

echo "passed: $pass_count"
