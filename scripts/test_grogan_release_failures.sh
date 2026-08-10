#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
ONE="$TMP_DIR/one.img"
TWO="$TMP_DIR/two.img"

fail() {
    echo "error: $1" >&2
    exit 1
}

bash -n "$ROOT/scripts/check_grogan_release.sh"
echo "ok: validator syntax"
"$ROOT/scripts/build_longmode_image.sh" "$ONE" > /dev/null
cp "$ONE" "$TWO"
printf '\000' | dd of="$TWO" bs=1 seek=1024 count=1 conv=notrunc status=none
if cmp -s "$ONE" "$TWO"; then
    fail "artifact-mutation: expected parity failure"
fi
echo "ok: artifact-mutation"
