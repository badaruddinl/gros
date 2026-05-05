#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/build/gros-v0.2.gro"

mkdir -p "$ROOT/build"
rm -f "$OUT"

# GrBoot v0.2 raw machine bytes.
# This does not compile C, Python, or assembly. It writes machine bytes directly to the file.
#
# 31 C0        xor ax, ax
# 8E D8        mov ds, ax
# BE 38 7C     mov si, banner
# E8 22 00     call print_string
# BE 44 7C     mov si, prompt
# E8 1C 00     call print_string
# 31 C0        xor ax, ax
# CD 16        int 0x16
# 3C 0D        cmp al, 0x0D
# 74 06        je enter
# B4 0E        mov ah, 0x0E
# CD 10        int 0x10
# EB F2        jmp read_key
# BE 49 7C     mov si, newline
# E8 08 00     call print_string
# BE 44 7C     mov si, prompt
# E8 02 00     call print_string
# EB E4        jmp read_key
# AC           lodsb
# 84 C0        test al, al
# 74 06        jz print_done
# B4 0E        mov ah, 0x0E
# CD 10        int 0x10
# EB F5        jmp print_string
# C3           ret

printf '%b' '\x31\xc0\x8e\xd8\xbe\x38\x7c\xe8\x22\x00\xbe\x44\x7c\xe8\x1c\x00\x31\xc0\xcd\x16\x3c\x0d\x74\x06\xb4\x0e\xcd\x10\xeb\xf2\xbe\x49\x7c\xe8\x08\x00\xbe\x44\x7c\xe8\x02\x00\xeb\xe4\xac\x84\xc0\x74\x06\xb4\x0e\xcd\x10\xeb\xf5\xc3' > "$OUT"
printf '%b' 'GrOS v0.2\r\n\x00gr> \x00\r\n\x00' >> "$OUT"

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
