#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STAGE1_SRC="$ROOT/boot/stage1_loader.gwn"
STAGE2_SRC="$ROOT/boot/stage2_min.gwn"
BUILD_DIR="$ROOT/build"
OUT=${1:-"$BUILD_DIR/gros-stage2.gwo"}

fail() {
    echo "error: $1" >&2
    exit 1
}

size_of() {
    wc -c < "$1" | tr -d ' '
}

signature_of() {
    tail -c 2 "$1" | od -An -tx1 | tr -d ' \n'
}

check_size() {
    local file=$1
    local expected=$2
    local name=$3
    local actual
    actual=$(size_of "$file")
    [ "$actual" = "$expected" ] || fail "$name must be $expected bytes, got $actual"
}

mkdir -p "$BUILD_DIR" "$(dirname -- "$OUT")"
TMP_DIR=$(mktemp -d "$BUILD_DIR/stage2-build.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

STAGE1="$TMP_DIR/stage1-loader.gwo"
STAGE2="$TMP_DIR/stage2-min.gwo"
HEADER="$TMP_DIR/stage2-header.gwo"
STAGE2_PAYLOAD="$TMP_DIR/stage2-payload.gwo"
FULL="$TMP_DIR/gros-stage2.gwo"

"$ROOT/scripts/gwnraw.sh" "$STAGE1_SRC" "$STAGE1"
"$ROOT/scripts/gwnraw.sh" "$STAGE2_SRC" "$STAGE2"

check_size "$STAGE1" 512 "stage-1"
check_size "$STAGE2" 2016 "stage-2 payload"
[ "$(signature_of "$STAGE1")" = "55aa" ] || fail "stage-1 boot signature must be 55aa"

printf '\x47\x52\x4f\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe0\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "$HEADER"
check_size "$HEADER" 32 "stage-2 header"
cat "$HEADER" "$STAGE2" > "$STAGE2_PAYLOAD"
check_size "$STAGE2_PAYLOAD" 2048 "headered stage-2"

cat "$STAGE1" "$STAGE2_PAYLOAD" > "$FULL"

FULL_SIZE=$(size_of "$FULL")
[ "$FULL_SIZE" = "2560" ] || fail "full image must be 2560 bytes, got $FULL_SIZE"
[ "$((FULL_SIZE % 512))" -eq 0 ] || fail "full image must be a multiple of 512 bytes"

mv "$FULL" "$OUT"

echo "built : $OUT"
echo "stage1: 512 bytes"
echo "stage2: 2048 bytes"
echo "total : $FULL_SIZE bytes"
