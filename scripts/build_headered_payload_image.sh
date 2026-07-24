#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PAYLOAD_SOURCE=${1:-}
OUT=${2:-}

usage() {
    echo "usage: build_headered_payload_image.sh <payload.gwn> <output.gwo>" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
}

size_of() { wc -c < "$1" | tr -d ' '; }

[ "$#" -eq 2 ] || { usage; exit 2; }
[ -f "$PAYLOAD_SOURCE" ] || fail "payload source file not found: $PAYLOAD_SOURCE"

mkdir -p "$(dirname -- "$OUT")"
TMP_DIR=$(mktemp -d "$ROOT/build/headered-payload.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

STAGE1="$TMP_DIR/stage1.gwo"
PAYLOAD="$TMP_DIR/payload.gwo"
HEADER="$TMP_DIR/header.gwo"
FULL="$TMP_DIR/full.gwo"

"$ROOT/scripts/gwnraw.sh" "$ROOT/boot/stage1_loader.gwn" "$STAGE1"
"$ROOT/scripts/gwnraw.sh" "$PAYLOAD_SOURCE" "$PAYLOAD"
[ "$(size_of "$STAGE1")" = 512 ] || fail "stage-1 must be 512 bytes"
[ "$(tail -c 2 "$STAGE1" | od -An -tx1 | tr -d ' \n')" = 55aa ] ||
    fail "stage-1 boot signature must be 55aa"
[ "$(size_of "$PAYLOAD")" = 2016 ] || fail "payload must be 2016 bytes"

printf '\x47\x52\x4f\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xe0\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "$HEADER"
cat "$STAGE1" "$HEADER" "$PAYLOAD" > "$FULL"
[ "$(size_of "$FULL")" = 2560 ] || fail "headered image must be 2560 bytes"
mv "$FULL" "$OUT"
echo "built: $OUT"
