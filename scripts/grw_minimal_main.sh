#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE='gros.x86.bios.real16.stage2.v0'
SOURCE=${1:-}
OUT=${2:-}

usage() {
    echo "usage: grw_minimal_main.sh <source.grw> <output.gwn>" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
}

[ "$#" -eq 2 ] || { usage; exit 2; }
[ -f "$SOURCE" ] || fail "source file not found: $SOURCE"

# This deliberately accepts one grammar production only. It does, however,
# implement the front-end seed's CRLF normalization and line comments.
grep -qE '/\*|\*/' "$SOURCE" && fail "block comments are reserved"
CLEAN=$(mktemp)
trap 'rm -f "$CLEAN"' EXIT
while IFS= read -r LINE || [ -n "$LINE" ]; do
    LINE=${LINE%$'\r'}
    LINE=${LINE%%//*}
    printf '%s\n' "$LINE" >> "$CLEAN"
done < "$SOURCE"
NORMALIZED=$(tr -d '[:space:]' < "$CLEAN")
EXPECTED="target\"$PROFILE\"fnmain()->void{return;}"
[ "$NORMALIZED" = "$EXPECTED" ] ||
    fail "unsupported source; expected target $PROFILE and fn main() -> void { return; }"

mkdir -p "$(dirname -- "$OUT")"
cat > "$OUT" <<'EOF'
; Compiler output for the Fase-4 minimal-main subset.
; Provenance: scripts/grw_minimal_main.sh
raw x86.bios.real16.generated.minimal_main_void.v1 {
    origin 8020
    label halt
    bytes FA
    bytes F4
    bytes EB
    rel8 halt
    pad_to 2016 with 00
}
EOF

echo "compiled: $SOURCE -> $OUT"
