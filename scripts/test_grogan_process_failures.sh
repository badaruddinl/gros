#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/image"
fail() { echo "error: $1" >&2; exit 1; }

"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
if "$ROOT/scripts/check_grogan_processes.sh" "$TMP_DIR/missing" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
    fail 'missing image was accepted'
fi
grep -F 'file not found' "$TMP_DIR/err" > /dev/null || fail 'missing-image diagnostic changed'
echo 'ok: missing process image rejected'

"$ROOT/scripts/check_grogan_processes.sh" "$IMAGE" > /dev/null
echo 'Grogan process failures: static process gate rejects missing artifacts'
