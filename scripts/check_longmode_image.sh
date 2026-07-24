#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}
fail() { echo "error: $1" >&2; exit 1; }
[ -f "$FILE" ] || fail "file not found: $FILE"
[ "$(wc -c < "$FILE" | tr -d ' ')" = 16896 ] || fail "long-mode image must be 16896 bytes"
[ "$(dd if="$FILE" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d ' \n')" = 55aa ] || fail "missing boot signature"
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')
require_hex() {
    case "$HEX" in *"$1"*) ;; *) fail "$2";; esac
}
require_hex 8816fe5f "missing boot-drive ABI storage"
require_hex c706fc5f "missing E820-count ABI storage"
require_hex b820e80000 "missing E820 query"
require_hex e4920c02e692 "missing A20 enable"
require_hex 0f0116 "missing GDT load"
require_hex 0f22c0 "missing CR0 transition"
require_hex 0f22d8 "missing CR3 page-table root"
require_hex 0f22e0 "missing CR4 PAE enable"
require_hex 0f30 "missing EFER write"
require_hex 0083 "missing 2MiB identity mapping"
echo "long mode image: BIOS bootstrap, boot-info ABI, and x86_64 transition structure ok"
