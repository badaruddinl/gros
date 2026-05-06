#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_runtime_abi.sh"
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

mutate_stage2_pattern() {
    local pattern=$1
    local stage2_offset absolute_offset

    stage2_offset=$(stage2_pattern_offset "$CASE_IMAGE" "$pattern")
    absolute_offset=$((512 + stage2_offset))
    printf '\000' |
        dd of="$CASE_IMAGE" bs=1 seek="$absolute_offset" count=1 conv=notrunc status=none
}

mutate_stage2_regex() {
    local pattern=$1
    local match

    match=$(printf '%s\n' "$(stage2_hex "$CASE_IMAGE")" | grep -Eo "$pattern" | head -n 1 || true)
    [ -n "$match" ] || fail "baseline image does not contain regex: $pattern"
    mutate_stage2_pattern "$match"
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
        missing-probe-call)
            mutate_stage2_pattern "31c0cd30"
            ;;
        missing-profile-id-text)
            mutate_stage2_pattern "67726f732e7838362e62696f732e7265616c31362e7374616765322e763000"
            ;;
        missing-write-cstr-helper)
            mutate_stage2_pattern "b80001cd30c3"
            ;;
        missing-write-char-echo-call)
            mutate_stage2_pattern "88c3aa41b80101cd30"
            ;;
        missing-write-crlf-call)
            mutate_stage2_pattern "b80201cd30"
            ;;
        missing-handler-frame)
            mutate_stage2_pattern "5589e5"
            ;;
        missing-probe-selector-branch)
            mutate_stage2_pattern "09c074"
            ;;
        missing-version-selector-branch)
            mutate_stage2_pattern "3d010074"
            ;;
        missing-profile-id-selector-branch)
            mutate_stage2_pattern "3d020074"
            ;;
        missing-write-cstr-selector-branch)
            mutate_stage2_pattern "3d000174"
            ;;
        missing-write-char-selector-branch)
            mutate_stage2_pattern "3d010174"
            ;;
        missing-write-crlf-selector-branch)
            mutate_stage2_pattern "3d020174"
            ;;
        missing-write-char-service-body)
            mutate_stage2_pattern "88d8b40ecd10"
            ;;
        missing-version-service-body)
            mutate_stage2_regex "b80100eb[0-9a-f]{2}"
            ;;
        missing-profile-id-service-body)
            mutate_stage2_regex "be[0-9a-f]{4}eb[0-9a-f]{2}"
            ;;
        missing-write-crlf-service-body)
            mutate_stage2_regex "56be[0-9a-f]{4}fce8[0-9a-f]{4}5eeb[0-9a-f]{2}"
            ;;
        missing-unsupported-return)
            mutate_stage2_pattern "b80100834e06015dcf"
            ;;
        missing-success-return)
            mutate_stage2_pattern "31c0836606fe5dcf"
            ;;
        missing-success-preserve-ax-return)
            mutate_stage2_pattern "836606fe5dcf"
            ;;
        missing-si-preservation)
            mutate_stage2_pattern "56fc"
            ;;
        *)
            fail "unknown runtime ABI negative test: $name"
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
expect_validator_failure "missing-probe-call" "missing runtime ABI byte fixture: runtime/control probe call"
expect_validator_failure "missing-profile-id-text" "missing runtime ABI byte fixture: runtime/control profile_id text"
expect_validator_failure "missing-write-cstr-helper" "missing runtime ABI byte fixture: console/text write selector call helper"
expect_validator_failure "missing-write-char-echo-call" "missing runtime ABI byte fixture: console/text write-char echo call"
expect_validator_failure "missing-write-crlf-call" "missing runtime ABI byte fixture: console/text write-crlf selector call"
expect_validator_failure "missing-handler-frame" "missing runtime ABI byte fixture: runtime interrupt handler stack frame"
expect_validator_failure "missing-probe-selector-branch" "missing runtime ABI byte fixture: runtime/control probe selector branch"
expect_validator_failure "missing-version-selector-branch" "missing runtime ABI byte fixture: runtime/control version selector branch"
expect_validator_failure "missing-profile-id-selector-branch" "missing runtime ABI byte fixture: runtime/control profile_id selector branch"
expect_validator_failure "missing-write-cstr-selector-branch" "missing runtime ABI byte fixture: console/text write selector branch"
expect_validator_failure "missing-write-char-selector-branch" "missing runtime ABI byte fixture: console/text write-char selector branch"
expect_validator_failure "missing-write-crlf-selector-branch" "missing runtime ABI byte fixture: console/text write-crlf selector branch"
expect_validator_failure "missing-write-char-service-body" "missing runtime ABI byte fixture: console/text write-char service body"
expect_validator_failure "missing-version-service-body" "missing runtime ABI byte fixture: runtime/control version returns AX=0001h and jumps to success"
expect_validator_failure "missing-profile-id-service-body" "missing runtime ABI byte fixture: runtime/control profile_id returns DS:SI and jumps to success"
expect_validator_failure "missing-write-crlf-service-body" "missing runtime ABI byte fixture: console/text write-crlf preserves SI and jumps to success"
expect_validator_failure "missing-unsupported-return" "missing runtime ABI byte fixture: unsupported selector returns CF=1 AX=0001h"
expect_validator_failure "missing-success-return" "missing runtime ABI byte fixture: successful selector returns CF=0 AX=0000h"
expect_validator_failure "missing-success-preserve-ax-return" "missing runtime ABI byte fixture: successful selector clears CF and preserves AX result"
expect_validator_failure "missing-si-preservation" "missing runtime ABI byte fixture: console/text preserves SI and falls through to success"

echo "passed: $pass_count"
