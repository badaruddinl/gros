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
expect_failure short-image "long-mode image must contain a 49664-byte kernel"
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
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
while :; do
    OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"4883c00f") { print (RSTART - 1) / 2; exit }')
    [ -n "$OFFSET" ] || break
    printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
done
expect_failure missing-heap-alignment "missing heap request rounding"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"48455031") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing first heap payload"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-heap-payload "missing first heap payload marker"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"ff5608") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing task dispatch"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-task-dispatch "missing task entry dispatch"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"c7461001000000") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing task state transition"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-task-state "missing completed-task state transition"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk '{ while (match($0,"47465331")) { answer = offset + RSTART - 1; offset += RSTART + 7; $0 = substr($0, RSTART + 8) } } END { if (answer != "") print answer / 2 }')
[ -n "$OFFSET" ] || fail "baseline missing filesystem superblock"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-fs-superblock "missing GFS1 filesystem image data"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk '{ while (match($0,"47524653")) { answer = offset + RSTART - 1; offset += RSTART + 7; $0 = substr($0, RSTART + 8) } } END { if (answer != "") print answer / 2 }')
[ -n "$OFFSET" ] || fail "baseline missing filesystem payload"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-fs-payload "missing filesystem payload data"
