#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE_ONE="$TMP_DIR/one.img"
IMAGE_TWO="$TMP_DIR/two.img"
GWO_ONE="$TMP_DIR/one.gwo"
GWO_TWO="$TMP_DIR/two.gwo"

fail() {
    echo "error: $1" >&2
    exit 1
}

"$ROOT/scripts/grw_grogan_x86_64.sh" \
    "$ROOT/examples/grogan/syscall-smoke.grw" "$GWO_ONE" > /dev/null
"$ROOT/scripts/grw_grogan_x86_64.sh" \
    "$ROOT/examples/grogan/syscall-smoke.grw" "$GWO_TWO" > /dev/null
cmp -s "$GWO_ONE" "$GWO_TWO" || fail "compiler artifact is not reproducible"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE_ONE" > /dev/null
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE_TWO" > /dev/null
cmp -s "$IMAGE_ONE" "$IMAGE_TWO" || fail "long-mode image is not reproducible"

echo "Grogan release: compiler artifact and x86_64 image are reproducible"
