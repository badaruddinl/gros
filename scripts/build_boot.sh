#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/build/gros-v0.1.gro"

mkdir -p "$ROOT/build"
rm -f "$OUT"

# GrBoot v0.1 raw machine bytes.
# This does not compile C, Python, or assembly. It writes machine bytes directly to the file.
#
# 31 C0        xor ax, ax
# 8E D8        mov ds, ax
# BE 16 7C     mov si, 0x7C16
# AC           lodsb
# 84 C0        test al, al
# 74 06        jz done
# B4 0E        mov ah, 0x0E
# CD 10        int 0x10
# EB F5        jmp print_loop
# FA           cli
# F4           hlt
# EB FD        jmp halt

printf $'\x31\xc0\x8e\xd8\xbe\x16\x7c\xac\x84\xc0\x74\x06\xb4\x0e\xcd\x10\xeb\xf5\xfa\xf4\xeb\xfd' > "$OUT"
printf $'GrOS v0.1\r\n\0' >> "$OUT"

SIZE=$(wc -c < "$OUT" | tr -d ' ')
PAD=$((510 - SIZE))

if [ "$PAD" -lt 0 ]; then
    echo "error: boot sector is too large: $SIZE bytes"
    exit 1
fi

dd if=/dev/zero bs=1 count="$PAD" >> "$OUT" 2>/dev/null
printf $'\x55\xaa' >> "$OUT"

FINAL_SIZE=$(wc -c < "$OUT" | tr -d ' ')
echo "built: $OUT"
echo "size : $FINAL_SIZE bytes"
