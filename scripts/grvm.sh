#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gwo2.c" "$ROOT/tools/grvm.c" -o "$TMP_DIR/grvm"
exec "$TMP_DIR/grvm" "$@"
