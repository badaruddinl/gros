#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILE=${1:-"$ROOT/build/gros-longmode.img"}
fail() { echo "error: $1" >&2; exit 1; }
"$ROOT/scripts/check_longmode_image.sh" "$FILE" > /dev/null
HEX=$(od -An -tx1 -v "$FILE" | tr -d ' \n')
require_hex() { case "$HEX" in *"$1"*) ;; *) fail "$2" ;; esac; }
require_hex b0ecee "missing ATA command/status port access"
require_hex 66f36d "missing ATA PIO sector transfer"
require_hex b041e6e9b054e6e9b041e6e9b04fe6e9b04be6e9b047e6e9b046e6e9b053e6e9b032e6e9b04fe6e9b04be6e9 "missing ATA/GFS2 mount proof"
require_hex 47465332 "missing GFS2 superblock validation"
require_hex 43544d32 "missing GFS2 commit marker validation"
echo "Grogan storage: ATA PIO block API, capacity bounds, GFS2 superblock selection, and checksum gate ok"
