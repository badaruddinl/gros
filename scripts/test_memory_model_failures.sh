#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_memory_model.sh"
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
    od -An -tx1 -v "$1" |
        tr -d ' \n'
}

stage2_hex() {
    dd if="$1" bs=512 skip=1 count=4 2> /dev/null |
        od -An -tx1 -v |
        tr -d ' \n'
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

mutate_image_pattern_byte() {
    local pattern=$1
    local image_offset

    image_offset=$(image_pattern_offset "$CASE_IMAGE" "$pattern")
    write_byte "$image_offset" 0
}

mutate_stage2_pattern_byte() {
    local pattern=$1
    local stage2_offset absolute_offset

    stage2_offset=$(stage2_pattern_offset "$CASE_IMAGE" "$pattern")
    absolute_offset=$((512 + stage2_offset))
    write_byte "$absolute_offset" 0
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
        missing-signature)
            printf '\000\000' |
                dd of="$CASE_IMAGE" bs=1 seek=510 count=2 conv=notrunc status=none
            ;;
        empty-stage2-payload)
            dd if=/dev/zero of="$CASE_IMAGE" bs=1 seek=512 count=2048 conv=notrunc status=none
            ;;
        missing-stage1-segment-stack)
            mutate_image_pattern_byte "fa31c08ed88ec08ed0bc007cfbfc"
            mutate_image_pattern_byte "fa31c08ed88ec08ed0bc007cfbfc"
            ;;
        missing-stage1-read)
            mutate_image_pattern_byte "b80402bb0080b90200"
            ;;
        missing-stage1-jump)
            mutate_image_pattern_byte "ea00800000"
            ;;
        missing-stage2-segment-stack)
            mutate_stage2_pattern_byte "fa31c08ed88ec08ed0bc007c"
            ;;
        missing-int30-offset)
            mutate_stage2_pattern_byte "c706c000"
            ;;
        missing-int30-segment)
            mutate_stage2_pattern_byte "c706c2000000"
            ;;
        missing-dssi-pointer-service)
            mutate_stage2_pattern_byte "b80001cd30c3"
            ;;
        *)
            fail "unknown memory model negative test: $name"
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
expect_validator_failure "missing-signature" "stage-1 boot signature must be 55aa"
expect_validator_failure "empty-stage2-payload" "stage-2 payload must not be empty"
expect_validator_failure "missing-stage1-segment-stack" "missing memory model byte fixture: stage-1 real16 segment and stack setup"
expect_validator_failure "missing-stage1-read" "missing memory model byte fixture: stage-1 reads 4 sectors to 0000:8000 from sector 2"
expect_validator_failure "missing-stage1-jump" "missing memory model byte fixture: stage-1 jumps to 0000:8000"
expect_validator_failure "missing-stage2-segment-stack" "missing memory model byte fixture: stage-2 real16 segment and stack setup"
expect_validator_failure "missing-int30-offset" "missing memory model byte fixture: stage-2 installs int 30h offset in IVT"
expect_validator_failure "missing-int30-segment" "missing memory model byte fixture: stage-2 installs int 30h segment 0000 in IVT"
expect_validator_failure "missing-dssi-pointer-service" "missing memory model byte fixture: runtime string service uses DS:SI near pointer"

echo "passed: $pass_count"
