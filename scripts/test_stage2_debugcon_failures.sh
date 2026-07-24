#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_stage2_debugcon.sh"
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

write_byte() {
    local offset=$1
    local value=$2

    printf '%b' "\\$(printf '%03o' "$value")" |
        dd of="$CASE_IMAGE" bs=1 seek="$offset" count=1 conv=notrunc status=none
}

stage2_pattern_offset() {
    local pattern=$1
    local hex prefix

    hex=$(dd if="$CASE_IMAGE" bs=512 skip=1 count=4 2> /dev/null | od -An -tx1 -v | tr -d ' \n')
    case "$hex" in
        *"$pattern"*) ;;
        *) fail "baseline image does not contain pattern: $pattern" ;;
    esac

    prefix=${hex%%"$pattern"*}
    printf '%s' "$((512 + ${#prefix} / 2))"
}

expect_failure() {
    local name=$1
    local expected=$2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    if "$VALIDATOR" "$CASE_IMAGE" > "$out" 2> "$err"; then
        fail "$name: expected failure"
    fi

    grep -F "$expected" "$out" "$err" > /dev/null || {
        cat "$out" >&2
        cat "$err" >&2
        fail "$name: expected error containing '$expected'"
    }

    pass "$name"
}

[ -f "$SOURCE_IMAGE" ] || fail "missing source stage-2 image: $SOURCE_IMAGE"

bash -n "$VALIDATOR"
pass "validator syntax"

copy_image_case "missing-string-mirror"
STRING_OFFSET=$(stage2_pattern_offset "ac84c07408e6e9b40ecd10")
write_byte "$((STRING_OFFSET + 5))" 0
expect_failure "missing-string-mirror" "missing stage-2 debug console mirror: string output path"

copy_image_case "missing-character-mirror"
CHAR_OFFSET=$(stage2_pattern_offset "88d8e6e9b40ecd10")
write_byte "$((CHAR_OFFSET + 2))" 0
expect_failure "missing-character-mirror" "missing stage-2 debug console mirror: character output path"

echo "passed: $pass_count"
