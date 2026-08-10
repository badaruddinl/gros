#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/check_grogan_x86_64_profile.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
IMAGE="$TMP_DIR/gros-longmode.img"

fail() {
    echo "error: $1" >&2
    exit 1
}

expect_failure() {
    local name=$1
    local expected=$2
    if "$VALIDATOR" "$IMAGE" > "$TMP_DIR/out" 2> "$TMP_DIR/err"; then
        fail "$name: expected failure"
    fi
    grep -F "$expected" "$TMP_DIR/err" > /dev/null || fail "$name: wrong error"
    echo "ok: $name"
}

bash -n "$VALIDATOR"
echo "ok: validator syntax"
"$ROOT/scripts/build_longmode_image.sh" "$IMAGE" > /dev/null
"$VALIDATOR" "$IMAGE" > /dev/null
echo "ok: baseline"

OFFSET=$(od -An -tx1 -v "$IMAGE" | tr -d ' \n' | awk 'match($0,"b04ce6e9b04de6e9b036e6e9b034e6e9b049e6e9b044e6e9b054e6e9b047e6e9b052e6e9b04fe6e9b036e6e9b034e6e9") { print (RSTART - 1) / 2; exit }')
[ -n "$OFFSET" ] || fail "baseline missing profile marker"
printf '\000' | dd of="$IMAGE" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none
expect_failure missing-profile-marker "missing Grogan x86_64 profile marker"
