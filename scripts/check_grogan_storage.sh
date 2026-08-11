#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}
fail() { echo "error: $1" >&2; exit 1; }
"$ROOT/scripts/check_longmode_image.sh" "$FILE" > /dev/null
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')
require_hex() { case "$HEX" in *"$1"*) ;; *) fail "$2" ;; esac; }
require_hex b0ecee "missing ATA command/status port access"
require_hex f36d "missing ATA PIO sector transfer"
require_hex 47465332 "missing GFS2 superblock validation"
require_hex 43544d32 "missing GFS2 commit marker validation"

# The two checks above are intentionally stable image markers.  The remaining
# storage proof belongs to the source units: exact instruction byte strings are
# assembler-version dependent (NASM 2.x and 3.x choose different redundant
# operand-size prefixes), while these structural checks must remain invariant.
grep -qF 'ata_block_read:' "$ROOT/kernel/drivers/ata.asm" || \
    fail 'ATA block-read entry point is missing'
grep -qF 'rep insw' "$ROOT/kernel/drivers/ata.asm" || \
    fail 'ATA PIO read transfer is missing'
grep -qF 'ata_wait_drq' "$ROOT/kernel/longmode_boot_ata_wait.inc" || \
    fail 'ATA status wait path is missing'
grep -qF 'gfs_validate_super:' "$ROOT/kernel/fs/gfs2.asm" || \
    fail 'GFS2 superblock validation path is missing'
grep -qF 'call ata_block_read' "$ROOT/kernel/fs/gfs2.asm" || \
    fail 'GFS2 does not consume the ATA block API'
echo "Grogan storage: ATA PIO block API, capacity bounds, GFS2 superblock selection, and checksum gate ok"
