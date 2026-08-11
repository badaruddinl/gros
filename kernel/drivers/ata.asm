fs_seed:
    ; Read-only boot-resident filesystem: superblock plus one root entry. Its
    ; payload is copied through heap_alloc, not accessed through a raw pointer.
    cmp dword [abs fs_image], 0x31534647 ; "GFS1"
    jne .fail
    cmp dword [abs fs_entry], 0x54494e49 ; root name "INIT"
    jne .fail
    mov edi, [abs fs_entry + 4]
    cmp edi, 4
    jne .fail
    mov rdi, 16
    call heap_alloc
    test rax, rax
    jz .fail
    mov rdi, rax
    mov rsi, fs_payload
    mov ecx, 4
    rep movsb
    cmp dword [rdi - 4], 0x53465247 ; "GRFS"
    jne .fail
    lea rax, [rdi - 4]
    mov [abs fs_payload_copy], rax
    mov byte [abs fs_loaded], 1
    mov al, 'F'
    out 0xe9, al
    mov al, 'S'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

%include "kernel/longmode_boot_ata_wait.inc"

ata_wait_idle:
    mov dx, ATA_PRIMARY_STATUS
    mov ecx, 0x100000
.poll:
    in al, dx
    test al, 0x80
    jnz .again
    test al, 1
    jnz .fail
    mov eax, 1
    ret
.again:
    dec ecx
    jnz .poll
.fail:
    xor eax, eax
    ret
ata_select_lba:
    ; RDI=LBA28 sector.  The command-specific caller writes 20h/30h after
    ; this register setup.
    mov r8, rdi
    mov dx, ATA_PRIMARY_DRIVE
    mov al, 0xe0
    mov rcx, r8
    shr rcx, 24
    and cl, 0x0f
    or al, cl
    out dx, al
    mov dx, ATA_PRIMARY_SECTOR_COUNT
    mov al, 1
    out dx, al
    mov dx, ATA_PRIMARY_LBA0
    mov rax, r8
    out dx, al
    inc dx
    shr rax, 8
    out dx, al
    inc dx
    shr rax, 8
    out dx, al
    ret

ata_probe:
    cli
    mov dx, ATA_PRIMARY_DRIVE
    mov al, 0xa0
    out dx, al
    xor al, al
    mov dx, ATA_PRIMARY_SECTOR_COUNT
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0xec
    out dx, al
    in al, dx
    test al, al
    jz .fail
    call ata_wait_drq
    test eax, eax
    jz .fail
    mov dx, ATA_PRIMARY_DATA
    mov rdi, ata_identify_buffer
    mov ecx, 256
    rep insw
    ; Prefer the 48-bit IDENTIFY capacity (words 100..103), falling back to
    ; the LBA28 count (words 60..61) for older ATA profiles.
    movzx rax, word [abs ata_identify_buffer + 200]
    movzx rdx, word [abs ata_identify_buffer + 202]
    shl rdx, 16
    or rax, rdx
    movzx rdx, word [abs ata_identify_buffer + 204]
    shl rdx, 32
    or rax, rdx
    movzx rdx, word [abs ata_identify_buffer + 206]
    shl rdx, 48
    or rax, rdx
    ; Some emulated ATA profiles expose a smaller legacy count even when the
    ; LBA48 words are present.  Keep the larger validated count so the real
    ; GFS2 surface after the boot transfer is not rejected as out of range.
    movzx rcx, word [abs ata_identify_buffer + 120]
    movzx rdx, word [abs ata_identify_buffer + 122]
    shl rdx, 16
    or rcx, rdx
    cmp rax, rcx
    cmovb rax, rcx
.capacity_ready:
    test rax, rax
    jz .fail
    mov [abs ata_capacity], rax
    mov byte [abs ata_ready], 1
    mov eax, 1
    ret
.fail:
    mov byte [abs ata_ready], 0
    xor eax, eax
    ret

ata_block_read:
    ; RDI=relative GFS2 block, RSI=512-byte kernel destination.
    cmp byte [abs ata_ready], 1
    jne .fail
    mov r8, [abs ata_capacity]
    cmp r8, FS_START_LBA
    jbe .range_fail
    sub r8, FS_START_LBA
    cmp rdi, r8
    jae .range_fail
    add rdi, FS_START_LBA
    push rsi
    call ata_select_lba
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0x20
    out dx, al
    call ata_wait_drq
    test eax, eax
    jz .pop_fail
    mov dx, ATA_PRIMARY_DATA
    pop rdi
    mov ecx, 256
    rep insw
    mov eax, 1
    ret
.pop_fail:
    pop rsi
.range_fail:
    mov byte [abs ata_failure_code], 3
.fail:
    xor eax, eax
    ret

ata_block_write:
    ; RDI=relative GFS2 block, RSI=512-byte kernel source.
    cmp byte [abs ata_ready], 1
    jne .fail
    mov r8, [abs ata_capacity]
    cmp r8, FS_START_LBA
    jbe .fail
    sub r8, FS_START_LBA
    cmp rdi, r8
    jae .fail
    add rdi, FS_START_LBA
    push rsi
    call ata_select_lba
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0x30
    out dx, al
    call ata_wait_drq
    test eax, eax
    jz .pop_fail
    mov dx, ATA_PRIMARY_DATA
    pop rsi
    mov ecx, 256
    rep outsw
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0xe7
    out dx, al
    call ata_wait_idle
    ret
.pop_fail:
    pop rsi
.fail:
    xor eax, eax
    ret
