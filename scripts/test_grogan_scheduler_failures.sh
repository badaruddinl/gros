#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_grogan_scheduler.sh"
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

HEX_FILE="$TMP_DIR/image.hex"
xxd -p "$IMAGE" | tr -d ' \n' > "$HEX_FILE"
FOUND=0
while IFS=: read -r CHAR_OFFSET _; do
    OFFSET=$((CHAR_OFFSET / 2))
    printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
    FOUND=1
done < <(grep -o -b "5053515256575541504151415241534154415541564157" "$HEX_FILE" || true)
[ "$FOUND" = 1 ] || fail "baseline missing timer register context save"
if "$VALIDATOR" "$IMAGE" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail "missing-context-save: expected failure"
fi
grep -F "missing complete timer register context save" "$TMP_DIR/err" > /dev/null \
    || fail "missing-context-save: wrong error"
echo "ok: missing-context-save"
