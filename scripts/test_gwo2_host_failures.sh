#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
FIXTURE="$TMP_DIR/gwo2_fixture"
GRVM="$TMP_DIR/grvm"

"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gwo2.c" "$ROOT/tools/gwo2_fixture.c" -o "$FIXTURE"
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gwo2.c" "$ROOT/tools/grvm.c" -o "$GRVM"

expect_failure() {
    local kind=$1
    "$FIXTURE" "$TMP_DIR/$kind.gwo" "$kind"
    if "$GRVM" "$TMP_DIR/$kind.gwo" > "$TMP_DIR/$kind.out" 2> "$TMP_DIR/$kind.err"; then
        echo "error: $kind fixture was accepted" >&2
        exit 1
    fi
    echo "ok: $kind rejected"
}

for kind in bad-magic bad-checksum overlap bad-size bad-entry unknown underflow nonboundary import; do
    expect_failure "$kind"
done

echo 'GWO2 host failures: malformed containers, control flow, stack effects, and imports rejected'
