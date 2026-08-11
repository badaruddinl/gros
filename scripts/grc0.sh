#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUSTC=${RUSTC:-rustc}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
command -v "$RUSTC" > /dev/null 2>&1 || { echo "error: $RUSTC is required" >&2; exit 1; }
"$RUSTC" --edition=2021 -O -D warnings "$ROOT/tools/grc0.rs" -o "$TMP_DIR/grc0"
exec "$TMP_DIR/grc0" "$@"
