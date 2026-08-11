#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}
KERNEL_BYTES=98816
FS_START_LBA=224
fail() { echo "error: $1" >&2; exit 1; }
[ -f "$FILE" ] || fail "file not found: $FILE"
[ "$(wc -c < "$FILE" | tr -d ' ')" -ge "$KERNEL_BYTES" ] || fail "long-mode image must contain a $KERNEL_BYTES-byte kernel"
[ "$(( $(wc -c < "$FILE" | tr -d ' ') % 512 ))" = 0 ] || fail "long-mode disk image must be a 512-byte multiple"
[ "$(dd if="$FILE" bs=1 skip=510 count=2 status=none | od -An -tx1 | tr -d ' \n')" = 55aa ] || fail "missing boot signature"
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')
require_hex() {
    case "$HEX" in *"$1"*) ;; *) fail "$2";; esac
}
require_hex_count() {
    local count
    count=$(printf '%s' "$HEX" | grep -o "$1" | wc -l | tr -d ' ')
    [ "$count" = "$2" ] || fail "$3"
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
require_hex b050e6e9b047e6e9b04de6e9b032e6e9 "missing second paging-window marker"
require_hex 0f011c25 "missing IDT load"
require_hex b047e6e9b057e6e9b04fe6e9b032e6e9b04fe6e9b04be6e9 "missing verified GWO2 loader marker"
require_hex b04ce6e9b04de6e9b036e6e9b034e6e9b049e6e9b044e6e9b054e6e9b047e6e9b052e6e9b04fe6e9b036e6e9b034e6e9 "missing Grogan x86_64 profile marker"
require_hex 0f0b "missing controlled invalid-opcode probe"
require_hex 8e00 "missing present kernel-only IDT gate"
require_hex be00600000 "missing E820 ownership scan base"
require_hex 483d00001000 "missing first-MiB reservation"
require_hex 4805ff0f0000482500f0ffff "missing E820 page alignment"
require_hex 46524d31 "missing physical frame ownership marker"
require_hex 4883c00f "missing heap request rounding"
require_hex 48c1e804 "missing heap slot conversion"
require_hex 48455031 "missing first heap payload marker"
require_hex 48455032 "missing second heap payload marker"
require_hex 48465231 "missing heap reuse marker"
require_hex 46524d32 "missing second physical frame marker"
require_hex bf28000000 "missing task descriptor allocation"
require_hex ff5608 "missing task entry dispatch"
require_hex c7461001000000 "missing completed-task state transition"
require_hex 47465331 "missing GFS1 filesystem superblock"
require_hex 494e4954 "missing INIT root entry"
require_hex f3a4 "missing filesystem read copy"
require_hex 47524653 "missing filesystem payload"
require_hex_count 47465331 2 "missing GFS1 filesystem image data"
require_hex_count 47524653 2 "missing filesystem payload data"
[ "$(dd if="$FILE" bs=1 skip="$((FS_START_LBA * 512))" count=4 status=none | od -An -tc | tr -d ' \n')" = GFS2 ] || fail "missing GFS2 disk superblock"
echo "Grogan x86_64 image: BIOS bootstrap, boot-info ABI, IDT, paging, frame pool, heap, scheduler, and filesystem seed ok"
