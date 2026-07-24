#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_headered_stage2_loader.sh"
SOURCE_IMAGE="$ROOT/dist/gros-stage2.gwo"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
CASE_IMAGE=""
pass() { pass_count=$((pass_count + 1)); echo "ok: $1"; }
fail() { echo "error: $1" >&2; exit 1; }
copy_case() { CASE_IMAGE="$TMP_DIR/$1.gwo"; cp "$SOURCE_IMAGE" "$CASE_IMAGE"; }
write_byte() { printf '%b' "\\$(printf '%03o' "$2")" | dd of="$CASE_IMAGE" bs=1 seek="$1" count=1 conv=notrunc status=none; }

expect_failure() {
    local name=$1 expected=$2 out="$TMP_DIR/$1.out" err="$TMP_DIR/$1.err"
    if "$VALIDATOR" "$CASE_IMAGE" > "$out" 2> "$err"; then fail "$name: expected failure"; fi
    grep -F "$expected" "$err" > /dev/null || { cat "$err" >&2; fail "$name: wrong error"; }
    pass "$name"
}

bash -n "$VALIDATOR"; pass "validator syntax"
copy_case baseline
"$VALIDATOR" "$CASE_IMAGE" > /dev/null
pass "baseline"

copy_case bad-header-magic
write_byte 512 0
expect_failure bad-header-magic "missing accepted headered stage-2 seed header"

copy_case bad-payload-size
write_byte 528 0
expect_failure bad-payload-size "missing accepted headered stage-2 seed header"

copy_case missing-dynamic-base
stage1_hex=$(od -An -tx1 -v "$CASE_IMAGE" | tr -d ' \n')
case "$stage1_hex" in
    *81c32080*) ;;
    *) fail "baseline image does not contain dynamic entry base" ;;
esac
prefix=${stage1_hex%%81c32080*}
write_byte "$(( ${#prefix} / 2 ))" 0
expect_failure missing-dynamic-base "stage-1 must add header size to entry offset"

echo "passed: $pass_count"
