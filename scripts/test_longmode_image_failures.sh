#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_longmode_image.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/gros-longmode.img"
fail() { echo "error: $1" >&2; exit 1; }
expect_failure() {
    local name=$1 expected=$2
    if "$VALIDATOR" "$IMAGE" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
        fail "$name: expected failure"
    fi
    grep -F "$expected" "$TMP_DIR/err" > /dev/null || fail "$name: wrong error"
    echo "ok: $name"
}
bash -n "$VALIDATOR"
echo "ok: validator syntax"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$VALIDATOR" "$IMAGE" > /dev/null
echo "ok: baseline"
truncate -s 512 "$IMAGE"
expect_failure short-image "long-mode image must be 16896 bytes"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
printf '\000' | dd of="$IMAGE" bs=1 seek=510 count=1 conv=notrunc status=none
expect_failure missing-signature "missing boot signature"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"e4920c02e692") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing A20 sequence"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-a20 "missing A20 enable"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"0f011c25") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing IDT load"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-idt "missing IDT load"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"46524d31") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing frame marker"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-frame-marker "missing physical frame ownership marker"
