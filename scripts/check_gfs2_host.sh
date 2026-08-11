#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/work.img"
TOOL="$TMP_DIR/gfs2"
OFFSET=4096
BLOCKS=128

command -v "$CC" > /dev/null 2>&1 || { echo "error: $CC is required" >&2; exit 1; }
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TOOL"
truncate -s "$((OFFSET + BLOCKS * 512))" "$IMAGE"
"$TOOL" format "$IMAGE" "$OFFSET" "$BLOCKS"
"$TOOL" check "$IMAGE" "$OFFSET" "$BLOCKS" > /dev/null

echo -n 'alpha source\n' > "$TMP_DIR/one.grw"
echo -n ' + appended\n' > "$TMP_DIR/tail.grw"
"$TOOL" put "$IMAGE" "$OFFSET" "$BLOCKS" hello.grw "$TMP_DIR/one.grw"
"$TOOL" append "$IMAGE" "$OFFSET" "$BLOCKS" hello.grw "$TMP_DIR/tail.grw"
"$TOOL" get "$IMAGE" "$OFFSET" "$BLOCKS" hello.grw "$TMP_DIR/roundtrip.grw"
cat "$TMP_DIR/one.grw" "$TMP_DIR/tail.grw" > "$TMP_DIR/expected.grw"
cmp -s "$TMP_DIR/roundtrip.grw" "$TMP_DIR/expected.grw"

echo -n 'truncated replacement\n' > "$TMP_DIR/replacement.grw"
"$TOOL" put "$IMAGE" "$OFFSET" "$BLOCKS" hello.grw "$TMP_DIR/replacement.grw"
"$TOOL" get "$IMAGE" "$OFFSET" "$BLOCKS" hello.grw "$TMP_DIR/replacement-roundtrip.grw"
cmp -s "$TMP_DIR/replacement.grw" "$TMP_DIR/replacement-roundtrip.grw"
"$TOOL" ls "$IMAGE" "$OFFSET" "$BLOCKS" | grep -F 'hello.grw' > /dev/null
"$TOOL" unlink "$IMAGE" "$OFFSET" "$BLOCKS" hello.grw
"$TOOL" check "$IMAGE" "$OFFSET" "$BLOCKS" > /dev/null
if "$TOOL" get "$IMAGE" "$OFFSET" "$BLOCKS" hello.grw "$TMP_DIR/missing" > /dev/null 2>&1; then
    echo 'error: deleted GFS2 file was readable' >&2
    exit 1
fi

echo 'GFS2 host path: format, remount, write, append, overwrite, unlink, and checker ok'
