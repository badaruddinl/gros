#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/corrupt.img"
LOG="$TMP_DIR/debug.log"
MONITOR_LOG="$TMP_DIR/monitor.log"
FS_OFFSET=122880
FS_BLOCKS=192

fail() { echo "error: $1" >&2; exit 1; }
command -v qemu-system-x86_64 > /dev/null 2>&1 || fail 'qemu-system-x86_64 is required'

GROGAN_USER_SOURCE="$ROOT/examples/grown-alpha/user-shell.grw" \
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gfs2.c" -o "$TMP_DIR/gfs2"
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gwo2.c" \
    "$ROOT/tools/gwo2_fixture.c" -o "$TMP_DIR/gwo2_fixture"
"$TMP_DIR/gfs2" get "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" grc1.gwo "$TMP_DIR/grc1.gwo"
# Corrupt the GWO2 magic in the persistent copy.  The ring-3 loader must
# reject it with an ordinary process-spawn error while the shell and kernel
# continue running.
printf '\000' | dd of="$TMP_DIR/grc1.gwo" bs=1 seek=0 conv=notrunc status=none
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" grc1.gwo "$TMP_DIR/grc1.gwo"
"$TMP_DIR/gwo2_fixture" "$TMP_DIR/invalid-import.gwo" import
"$TMP_DIR/gfs2" put "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" invalid-import.gwo \
    "$TMP_DIR/invalid-import.gwo"
"$TMP_DIR/gfs2" check "$IMAGE" "$FS_OFFSET" "$FS_BLOCKS" > /dev/null

set +e
{
    sleep 5
    printf 'sendkey r\n'; sleep 0.08
    printf 'sendkey u\n'; sleep 0.08
    printf 'sendkey n\n'; sleep 0.08
    printf 'sendkey spc\n'; sleep 0.08
    printf 'sendkey g\n'; sleep 0.08
    printf 'sendkey r\n'; sleep 0.08
    printf 'sendkey c\n'; sleep 0.08
    printf 'sendkey 1\n'; sleep 0.08
    printf 'sendkey dot\n'; sleep 0.08
    printf 'sendkey g\n'; sleep 0.08
    printf 'sendkey w\n'; sleep 0.08
    printf 'sendkey o\n'; sleep 0.08
    printf 'sendkey ret\n'; sleep 2
    printf 'sendkey r\n'; sleep 0.08
    printf 'sendkey u\n'; sleep 0.08
    printf 'sendkey n\n'; sleep 0.08
    printf 'sendkey spc\n'; sleep 0.08
    printf 'sendkey i\n'; sleep 0.08
    printf 'sendkey n\n'; sleep 0.08
    printf 'sendkey v\n'; sleep 0.08
    printf 'sendkey a\n'; sleep 0.08
    printf 'sendkey l\n'; sleep 0.08
    printf 'sendkey i\n'; sleep 0.08
    printf 'sendkey d\n'; sleep 0.08
    printf 'sendkey minus\n'; sleep 0.08
    printf 'sendkey i\n'; sleep 0.08
    printf 'sendkey m\n'; sleep 0.08
    printf 'sendkey p\n'; sleep 0.08
    printf 'sendkey o\n'; sleep 0.08
    printf 'sendkey r\n'; sleep 0.08
    printf 'sendkey t\n'; sleep 0.08
    printf 'sendkey dot\n'; sleep 0.08
    printf 'sendkey g\n'; sleep 0.08
    printf 'sendkey w\n'; sleep 0.08
    printf 'sendkey o\n'; sleep 0.08
    printf 'sendkey ret\n'; sleep 2
    printf 'sendkey e\n'; sleep 0.08
    printf 'sendkey x\n'; sleep 0.08
    printf 'sendkey i\n'; sleep 0.08
    printf 'sendkey t\n'; sleep 0.08
    printf 'sendkey ret\n'; sleep 2
    printf 'quit\n'
} | timeout 30 qemu-system-x86_64 \
    -drive format=raw,file="$IMAGE" \
    -display none -monitor stdio -no-reboot -no-shutdown \
    -debugcon "file:$LOG" -global isa-debugcon.iobase=0xe9 \
    > "$MONITOR_LOG" 2>&1
status=$?
set -e
[ "$status" = 0 ] || { tail -c 4000 "$MONITOR_LOG" >&2; fail "qemu status $status"; }
run_failures=$(grep -ao 'RUN FAIL' "$LOG" | wc -l | tr -d ' ')
[ "$run_failures" -ge 2 ] || fail 'malformed or unsupported GWO2 was accepted'
grep -aF 'USEROK' "$LOG" > /dev/null || fail 'kernel did not recover after corrupt GWO2'

echo 'Grogan corruption: malformed persistent GWO2 rejected without kernel failure'
