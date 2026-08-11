#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE_ONE="$TMP_DIR/one.img"
IMAGE_TWO="$TMP_DIR/two.img"
GWO_ONE="$TMP_DIR/one.gwo"
GWO_TWO="$TMP_DIR/two.gwo"
MANIFEST_ONE="$TMP_DIR/manifest-one.txt"
MANIFEST_TWO="$TMP_DIR/manifest-two.txt"

fail() {
    echo "error: $1" >&2
    exit 1
}

"$ROOT/scripts/grc0.sh" \
    "$ROOT/examples/grown-alpha/hello.grw" "$GWO_ONE"
"$ROOT/scripts/grc0.sh" \
    "$ROOT/examples/grown-alpha/hello.grw" "$GWO_TWO"
cmp -s "$GWO_ONE" "$GWO_TWO" || fail "compiler artifact is not reproducible"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE_ONE" > /dev/null
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE_TWO" > /dev/null
cmp -s "$IMAGE_ONE" "$IMAGE_TWO" || fail "long-mode image is not reproducible"
"$ROOT/scripts/check_longmode_image.sh" "$IMAGE_ONE" > /dev/null
"$ROOT/scripts/check_longmode_image.sh" "$IMAGE_TWO" > /dev/null
{
    printf 'compiler '
    sha256sum "$GWO_ONE" | awk '{print $1}'
    printf 'image '
    sha256sum "$IMAGE_ONE" | awk '{print $1}'
} > "$MANIFEST_ONE"
{
    printf 'compiler '
    sha256sum "$GWO_TWO" | awk '{print $1}'
    printf 'image '
    sha256sum "$IMAGE_TWO" | awk '{print $1}'
} > "$MANIFEST_TWO"
cmp -s "$MANIFEST_ONE" "$MANIFEST_TWO" || fail "artifact manifest is not reproducible"

echo "Grogan release: compiler/image artifacts and SHA-256 manifest are reproducible"
