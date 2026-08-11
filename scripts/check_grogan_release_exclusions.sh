#!/usr/bin/env bash
set -euo pipefail

# Validation-only fault hooks are opt-in NASM defines.  This gate checks the
# exact release build path and refuses an image whose preprocessed kernel still
# carries test-only symbols or marker strings.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
fail() { echo "error: $1" >&2; exit 1; }

"$ROOT/scripts/build_longmode_image.sh" "$TMP_DIR/release.img" > /dev/null
(cd "$ROOT" && nasm -E kernel/longmode_boot.asm -o "$TMP_DIR/release.preprocessed.asm")
for symbol in process_create_test_active process_create_test_attempt process_create_test_counter resource_test_frames_live resource_test_handles_live forced_timeout; do
    if grep -F "$symbol" "$TMP_DIR/release.preprocessed.asm" > /dev/null; then
        fail "release preprocessed kernel contains validation-only symbol $symbol"
    fi
done
for marker in PCA PCF PCS R00000000H; do
    if grep -aF "$marker" "$TMP_DIR/release.img" > /dev/null; then
        fail "release image contains validation marker $marker"
    fi
done
echo 'Grogan release exclusions: process, resource, and ATA fault hooks are absent from the normal image'
