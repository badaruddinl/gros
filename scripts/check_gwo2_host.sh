#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
GRCD="$TMP_DIR/grc0"
GRVM="$TMP_DIR/grvm"
SOURCE="$ROOT/examples/grown-alpha/hello.grw"
STORAGE_SOURCE="$ROOT/examples/grown-alpha/storage-smoke.grw"

command -v "$CC" > /dev/null 2>&1 || { echo "error: $CC is required" >&2; exit 1; }
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gwo2.c" "$ROOT/tools/grc0.c" -o "$GRCD"
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gwo2.c" "$ROOT/tools/grvm.c" -o "$GRVM"
"$GRCD" "$SOURCE" "$TMP_DIR/hello-a.gwo"
"$GRCD" "$SOURCE" "$TMP_DIR/hello-b.gwo"
cmp -s "$TMP_DIR/hello-a.gwo" "$TMP_DIR/hello-b.gwo"
[ "$("$GRVM" "$TMP_DIR/hello-a.gwo")" = 28 ]

"$GRCD" "$STORAGE_SOURCE" "$TMP_DIR/storage.gwo"
[ "$(cd "$TMP_DIR" && "$GRVM" storage.gwo)" = A ] || {
    echo 'error: GWO2 storage imports did not round-trip bytes' >&2
    exit 1
}
[ ! -e "$TMP_DIR/vm-storage-smoke.grw" ] || {
    echo 'error: GWO2 storage unlink import did not remove the file' >&2
    exit 1
}

echo 'GWO2 host path: deterministic compiler, bytecode VM, and file/byte imports ok'
