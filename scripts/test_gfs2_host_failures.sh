#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/base.img"
TOOL="$TMP_DIR/gfs2"
OFFSET=0
BLOCKS=128

fail() { echo "error: $1" >&2; exit 1; }
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TOOL"
truncate -s "$((BLOCKS * 512))" "$IMAGE"
"$TOOL" format "$IMAGE" "$OFFSET" "$BLOCKS"
echo -n 'fixture' > "$TMP_DIR/file"
"$TOOL" put "$IMAGE" "$OFFSET" "$BLOCKS" fixture.grw "$TMP_DIR/file"
"$TOOL" check "$IMAGE" "$OFFSET" "$BLOCKS" > /dev/null

expect_failure() {
    local name=$1 expected=$2
    if "$TOOL" check "$TMP_DIR/case.img" "$OFFSET" "$BLOCKS" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
        fail "$name: expected rejection"
    fi
    grep -F "$expected" "$TMP_DIR/err" > /dev/null || fail "$name: wrong diagnostic"
    echo "ok: $name"
}

cp "$IMAGE" "$TMP_DIR/case.img"
printf '\x00' | dd of="$TMP_DIR/case.img" bs=1 seek=0 conv=notrunc status=none
printf '\x00' | dd of="$TMP_DIR/case.img" bs=1 seek=512 conv=notrunc status=none
expect_failure bad-magic 'no valid GFS2 superblock'

cp "$IMAGE" "$TMP_DIR/case.img"
printf '\x00' | dd of="$TMP_DIR/case.img" bs=1 seek=52 conv=notrunc status=none
printf '\x00' | dd of="$TMP_DIR/case.img" bs=1 seek=$((512 + 52)) conv=notrunc status=none
expect_failure bad-checksum 'no valid GFS2 superblock'

cp "$IMAGE" "$TMP_DIR/case.img"
printf '\x00' | dd of="$TMP_DIR/case.img" bs=1 seek=$((2 * 512)) conv=notrunc status=none
expect_failure bitmap-disagreement 'allocation bitmap disagreement'

cp "$IMAGE" "$TMP_DIR/case.img"
printf '\x80\x00\x00\x00\x00\x00\x00\x00' | dd of="$TMP_DIR/case.img" bs=1 seek=$((3 * 512 + 128 + 24)) conv=notrunc status=none
expect_failure extent-metadata 'directory references invalid inode'

echo 'GFS2 host failures: corrupt superblocks, bitmap, and extents are rejected'
