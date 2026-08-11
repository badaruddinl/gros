#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
"$CC" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/tools/gwo2.c" "$ROOT/tools/grc0.c" -o "$TMP_DIR/grc0"
exec "$TMP_DIR/grc0" "$@"
