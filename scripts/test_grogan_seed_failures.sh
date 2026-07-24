#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_grogan_seed.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/gros-stage2.gwo"
fail() { echo "error: $1" >&2; exit 1; }
bash -n "$VALIDATOR"
echo "ok: validator syntax"
"$ROOT/scripts/build_stage2_image.sh" > /dev/null
cp "$ROOT/build/gros-stage2.gwo" "$IMAGE"
"$VALIDATOR" "$IMAGE" > /dev/null
echo "ok: baseline"
OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"4752474e") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing Grogan magic"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
if "$VALIDATOR" "$IMAGE" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail "missing-magic: expected failure"
fi
grep -F 'missing Grogan state magic bytes' "$TMP_DIR/err" > /dev/null || fail "missing-magic: wrong error"
echo "ok: missing magic"
