#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_grogan_syscalls.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/gros-longmode.img"

fail() {
    echo "error: $1" >&2
    exit 1
}

bash -n "$VALIDATOR"
echo "ok: validator syntax"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$VALIDATOR" "$IMAGE" > /dev/null
echo "ok: baseline"

while :; do
    HEX=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n')
    OFFSET=$(printf '%s' "$HEX" | awk 'match($0,"480f07") { print (RSTART - 1) / 2; exit }')
    [ -n "$OFFSET" ] || break
    printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
done
if "$VALIDATOR" "$IMAGE" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail "missing-sysretq: expected failure"
fi
grep -F "missing SYSRETQ return path" "$TMP_DIR/err" > /dev/null \
    || fail "missing-sysretq: wrong error"
echo "ok: missing-sysretq"
