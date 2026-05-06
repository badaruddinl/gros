#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_stage2_image.sh"
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

image_hex() {
    od -An -tx1 -v "$1" |
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

mutate_stage2_pattern_byte() {
    local pattern=$1
    local relative_offset=$2
    local value=$3
    local stage2_offset absolute_offset

    stage2_offset=$(stage2_pattern_offset "$CASE_IMAGE" "$pattern")
    absolute_offset=$((512 + stage2_offset + relative_offset))
    write_byte "$absolute_offset" "$value"
}

mutate_image_pattern_byte() {
    local pattern=$1
    local relative_offset=$2
    local value=$3
    local image_offset absolute_offset

    image_offset=$(image_pattern_offset "$CASE_IMAGE" "$pattern")
    absolute_offset=$((image_offset + relative_offset))
    write_byte "$absolute_offset" "$value"
}

mutate_text() {
    local text=$1
    local offsets offset

    offsets=$(LC_ALL=C grep -aboF "$text" "$CASE_IMAGE" | cut -d: -f1)
    [ -n "$offsets" ] || fail "baseline image does not contain text: $text"

    while IFS= read -r offset; do
        [ -n "$offset" ] || continue
        write_byte "$offset" 0
    done <<EOF
$offsets
EOF
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
        missing-sector-read-count)
            mutate_image_pattern_byte "b80402" 0 0
            ;;
        missing-stage2-load-offset)
            mutate_image_pattern_byte "bb0080" 0 0
            ;;
        missing-starting-sector)
            mutate_image_pattern_byte "b90200" 0 0
            ;;
        missing-bios-disk-read)
            mutate_image_pattern_byte "cd13" 0 0
            mutate_image_pattern_byte "cd13" 0 0
            ;;
        missing-stage2-far-jump)
            mutate_image_pattern_byte "ea00800000" 0 0
            ;;
        missing-banner)
            mutate_text "GrOS v0.5"
            ;;
        missing-prompt)
            mutate_text "ground> "
            ;;
        missing-int30-vector-offset)
            mutate_stage2_pattern_byte "c706c000c680" 0 0
            ;;
        missing-int30-vector-segment)
            mutate_stage2_pattern_byte "c706c2000000" 0 0
            ;;
        handler-out-of-range)
            mutate_stage2_pattern_byte "c706c000c680" 5 136
            ;;
        *)
            fail "unknown stage-2 image negative test: $name"
            ;;
    esac

    if "$VALIDATOR" --require-ndisasm "$CASE_IMAGE" > "$out" 2> "$err"; then
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
"$VALIDATOR" --require-ndisasm "$CASE_IMAGE" > /dev/null
pass "baseline image"

expect_validator_failure "wrong-size" "stage-2 boot image must be 2560 bytes"
expect_validator_failure "missing-signature" "stage-1 boot signature must be 55aa"
expect_validator_failure "empty-stage2-payload" "stage-2 payload must not be empty"
expect_validator_failure "missing-sector-read-count" "missing expected instruction: stage-2 sector read count"
expect_validator_failure "missing-stage2-load-offset" "missing expected instruction: stage-2 load offset"
expect_validator_failure "missing-starting-sector" "missing expected instruction: stage-2 starting sector"
expect_validator_failure "missing-bios-disk-read" "missing expected instruction: BIOS disk read interrupt"
expect_validator_failure "missing-stage2-far-jump" "missing expected instruction: stage-2 far jump"
expect_validator_failure "missing-banner" "missing expected text: stage-2 banner"
expect_validator_failure "missing-prompt" "missing expected text: stage-2 prompt"
expect_validator_failure "missing-int30-vector-offset" "missing expected instruction: int 30h IVT offset install"
expect_validator_failure "missing-int30-vector-segment" "missing expected instruction: int 30h IVT segment install"
expect_validator_failure "handler-out-of-range" "int 30h handler must be inside stage-2 payload"

echo "passed: $pass_count"
