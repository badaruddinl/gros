#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROFILE='gros.x86.bios.longmode.grogan.v0'
SOURCE=${1:-}
OUT=${2:-}

usage() {
    echo "usage: grw_grogan_x86_64.sh <source.grw> <output.gwo>" >&2
}

fail() {
    echo "error: $1" >&2
    exit 1
}

[ "$#" -eq 2 ] || { usage; exit 2; }
[ -f "$SOURCE" ] || fail "source file not found: $SOURCE"

grep -qE '/\*|\*/' "$SOURCE" && fail "block comments are reserved"
CLEAN=$(mktemp)
PAYLOAD=$(mktemp)
trap 'rm -f "$CLEAN" "$PAYLOAD"' EXIT
while IFS= read -r LINE || [ -n "$LINE" ]; do
    LINE=${LINE%$'\r'}
    LINE=${LINE%%//*}
    printf '%s\n' "$LINE" >> "$CLEAN"
done < "$SOURCE"

NORMALIZED=$(tr -d '[:space:]' < "$CLEAN")
EXPECTED="target\"$PROFILE\"fnmain()->void{grogan::write();grogan::exit();}"
[ "$NORMALIZED" = "$EXPECTED" ] ||
    fail "unsupported source; expected target $PROFILE with grogan::write() and grogan::exit()"

# The Alpha syscall ABI lowers write (selector 2), then process_exit
# (selector 0x0b), followed by a bounded wait loop.  The payload is still a
# native bootstrap artifact; GWO2 bytecode is introduced by the toolchain
# workstream and is never silently substituted for this ABI.
printf '\xb8\x02\x00\x00\x00\x0f\x05\xb8\x0b\x00\x00\x00\x0f\x05\xf4\xeb\xfd' > "$PAYLOAD"
PAYLOAD_SIZE=$(wc -c < "$PAYLOAD" | tr -d ' ')
[ "$PAYLOAD_SIZE" -le 128 ] || fail "generated payload exceeds GWO bounded size"
CHECKSUM=$(od -An -tu1 -v "$PAYLOAD" | awk '{ for (i = 1; i <= NF; i++) sum += $i } END { print sum + 0 }')
[ "$CHECKSUM" -le 65535 ] || fail "generated payload checksum exceeds GWO field"

mkdir -p "$(dirname -- "$OUT")"
printf '\x47\x57\x4f\x31\x01\x00\x00\x00\x18\x00\x00\x00' > "$OUT"
printf '%b' "\\x$(printf '%02x' "$PAYLOAD_SIZE")\\x00\\x00\\x00" >> "$OUT"
printf '\x00\x00\x00\x00' >> "$OUT"
CHECKSUM_LO=$(printf '%02x' "$((CHECKSUM & 255))")
CHECKSUM_HI=$(printf '%02x' "$((CHECKSUM >> 8))")
printf '%b' "\\x${CHECKSUM_LO}\\x${CHECKSUM_HI}\\x00\\x00" >> "$OUT"
cat "$PAYLOAD" >> "$OUT"
[ "$(wc -c < "$OUT" | tr -d ' ')" = "$((24 + PAYLOAD_SIZE))" ] || fail "generated GWO size mismatch"

echo "compiled: $SOURCE -> $OUT (GWO1, payload ${PAYLOAD_SIZE} bytes, checksum ${CHECKSUM})"
