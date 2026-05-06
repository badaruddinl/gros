#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_BOOT="$ROOT/scripts/check_boot.sh"
VALIDATE_BOOT="$ROOT/scripts/validate_boot_image.sh"
SOURCE_IMAGE="$ROOT/dist/gros-v0.5.gwo"
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
    CASE_IMAGE="$case_root/gros-v0.5.gwo"
    cp "$SOURCE_IMAGE" "$CASE_IMAGE"
}

write_byte() {
    local offset=$1
    local value=$2

    printf '%b' "\\$(printf '%03o' "$value")" |
        dd of="$CASE_IMAGE" bs=1 seek="$offset" count=1 conv=notrunc status=none
}

mutate_binary_pattern_first_byte_all() {
    local pattern=$1
    local value=$2
    local offsets offset

    offsets=$(LC_ALL=C grep -aboF "$pattern" "$CASE_IMAGE" | cut -d: -f1)
    [ -n "$offsets" ] || fail "baseline image does not contain binary pattern"

    while IFS= read -r offset; do
        [ -n "$offset" ] || continue
        write_byte "$offset" "$value"
    done <<EOF
$offsets
EOF
}

expect_failure() {
    local name=$1
    local expected=$2
    shift 2
    local out="$TMP_DIR/$name.out"
    local err="$TMP_DIR/$name.err"

    if "$@" > "$out" 2> "$err"; then
        fail "$name: expected failure"
    fi

    if ! grep -F "$expected" "$out" "$err" > /dev/null; then
        echo "stdout:" >&2
        cat "$out" >&2
        echo "stderr:" >&2
        cat "$err" >&2
        fail "$name: expected error containing '$expected'"
    fi

    pass "$name"
}

expect_check_boot_failure() {
    local name=$1
    local expected=$2

    copy_image_case "$name"

    case "$name" in
        check-missing-file)
            rm -f "$CASE_IMAGE"
            ;;
        check-wrong-size)
            truncate -s 511 "$CASE_IMAGE"
            ;;
        check-wrong-size-long)
            truncate -s 513 "$CASE_IMAGE"
            ;;
        check-missing-signature)
            printf '\000\000' |
                dd of="$CASE_IMAGE" bs=1 seek=510 count=2 conv=notrunc status=none
            ;;
        *)
            fail "unknown check_boot negative test: $name"
            ;;
    esac

    expect_failure "$name" "$expected" "$CHECK_BOOT" "$CASE_IMAGE"
}

expect_validate_boot_failure() {
    local name=$1
    local expected=$2

    copy_image_case "$name"

    case "$name" in
        validate-missing-file)
            rm -f "$CASE_IMAGE"
            ;;
        validate-wrong-size)
            truncate -s 511 "$CASE_IMAGE"
            ;;
        validate-wrong-size-long)
            truncate -s 513 "$CASE_IMAGE"
            ;;
        validate-missing-signature)
            printf '\000\000' |
                dd of="$CASE_IMAGE" bs=1 seek=510 count=2 conv=notrunc status=none
            ;;
        validate-empty-payload)
            dd if=/dev/zero of="$CASE_IMAGE" bs=1 count=510 conv=notrunc status=none
            ;;
        validate-missing-video-int)
            mutate_binary_pattern_first_byte_all "$(printf '\315\020')" 0
            ;;
        validate-missing-keyboard-int)
            mutate_binary_pattern_first_byte_all "$(printf '\315\026')" 0
            ;;
        validate-missing-bootstrap-int)
            mutate_binary_pattern_first_byte_all "$(printf '\315\031')" 0
            ;;
        *)
            fail "unknown validate_boot_image negative test: $name"
            ;;
    esac

    expect_failure "$name" "$expected" "$VALIDATE_BOOT" --require-ndisasm "$CASE_IMAGE"
}

[ -f "$SOURCE_IMAGE" ] || fail "missing source boot image: $SOURCE_IMAGE"

bash -n "$CHECK_BOOT" "$VALIDATE_BOOT"
pass "validator syntax"

copy_image_case "check-baseline"
"$CHECK_BOOT" "$CASE_IMAGE" > /dev/null
pass "check_boot baseline"

copy_image_case "validate-baseline"
"$VALIDATE_BOOT" --require-ndisasm "$CASE_IMAGE" > /dev/null
pass "validate_boot_image baseline"

expect_failure "validate-unknown-option" "usage:" "$VALIDATE_BOOT" --unknown
expect_failure "validate-too-many-args" "usage:" "$VALIDATE_BOOT" "$SOURCE_IMAGE" "$SOURCE_IMAGE"

expect_check_boot_failure "check-missing-file" "error: file not found:"
expect_check_boot_failure "check-wrong-size" "error: boot sector must be 512 bytes"
expect_check_boot_failure "check-wrong-size-long" "error: boot sector must be 512 bytes"
expect_check_boot_failure "check-missing-signature" "error: boot signature must be 55aa"

expect_validate_boot_failure "validate-missing-file" "error: file not found:"
expect_validate_boot_failure "validate-wrong-size" "error: boot sector must be exactly 512 bytes"
expect_validate_boot_failure "validate-wrong-size-long" "error: boot sector must be exactly 512 bytes"
expect_validate_boot_failure "validate-missing-signature" "error: boot signature must be 55aa"
expect_validate_boot_failure "validate-empty-payload" "error: missing expected instruction: BIOS video interrupt"
expect_validate_boot_failure "validate-missing-video-int" "error: missing expected instruction: BIOS video interrupt"
expect_validate_boot_failure "validate-missing-keyboard-int" "error: missing expected instruction: BIOS keyboard interrupt"
expect_validate_boot_failure "validate-missing-bootstrap-int" "error: missing expected instruction: BIOS bootstrap interrupt"

echo "passed: $pass_count"
