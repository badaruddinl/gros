gfs_checksum:
    ; RDI=superblock bytes.  The host and kernel use the same FNV-1a-32
    ; checksum over the first 52 bytes.
    mov eax, 2166136261
    mov ecx, 52
.sum:
    movzx edx, byte [rdi]
    xor eax, edx
    imul eax, 16777619
    inc rdi
    dec ecx
    jnz .sum
    ret

gfs_validate_super:
    cmp dword [rdi], 0x32534647 ; GFS2
    jne .bad
    cmp word [rdi + 4], 2
    jne .bad
    cmp word [rdi + 6], 512
    jne .bad
    cmp dword [rdi + 56], 0x324d5443 ; CMT2
    jne .bad
    push rdi
    call gfs_checksum
    pop rdi
    cmp eax, [rdi + 52]
    jne .bad
    mov rax, [rdi + 16]
    test rax, rax
    jz .bad
    mov r8, [abs ata_capacity]
    add rax, FS_START_LBA
    jc .bad
    cmp rax, r8
    ja .bad
    cmp dword [rdi + 32], 1
    jne .bad
    cmp dword [rdi + 44], 32
    jne .bad
    cmp dword [rdi + 48], 1
    jne .bad
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

gfs_mount:
    mov byte [abs gfs_active_super], 0
    xor edi, edi
    mov rsi, gfs_super_buffer
    call ata_block_read
    test eax, eax
    jz .bad
    mov rdi, gfs_super_buffer
    call gfs_validate_super
    mov ebx, eax
    xor edi, edi
    mov rsi, gfs_recovery_buffer
    mov edi, 1
    call ata_block_read
    test eax, eax
    jz .choose_primary
    mov rdi, gfs_recovery_buffer
    call gfs_validate_super
    test eax, eax
    jz .choose_primary
    cmp ebx, 1
    jne .choose_recovery
    mov rax, [abs gfs_recovery_buffer + 8]
    cmp rax, [abs gfs_super_buffer + 8]
    jbe .choose_primary
.choose_recovery:
    mov rsi, gfs_recovery_buffer
    mov rdi, gfs_super_buffer
    mov ecx, 64
    rep movsq
    mov byte [abs gfs_active_super], 1
.choose_primary:
    mov rdi, gfs_super_buffer
    call gfs_validate_super
    test eax, eax
    jz .bad
    mov rax, [abs gfs_super_buffer + 16]
    mov [abs gfs_total_blocks], rax
    mov byte [abs gfs_mount_valid], 1
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

storage_seed:
    call ata_probe
    test eax, eax
    jz .fail
    call gfs_mount
    test eax, eax
    jz .fail
    mov al, 'A'
    out 0xe9, al
    mov al, 'T'
    out 0xe9, al
    mov al, 'A'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    mov al, 'G'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    mov al, 'S'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    ret
.fail:
    ; A storage probe/mount failure is a deliberate boot stop, but it must be
    ; observable and bounded so device-error tests can distinguish it from an
    ; ATA polling hang.
    mov al, 'A'
    out 0xe9, al
    mov al, 'T'
    out 0xe9, al
    mov al, 'A'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    mov al, 'A'
    out 0xe9, al
    mov al, 'I'
    out 0xe9, al
    mov al, 'L'
    out 0xe9, al
    cli
.halt: hlt
    jmp .halt

; -------------------------- GFS2 kernel file path -------------------------
; The first kernel-visible file profile is deliberately bounded to one root
; directory and one 512-byte extent per regular file.  The on-disk metadata,
; checksums, allocation bitmap, inactive-superblock commit, and ATA writes are
; nevertheless real GFS2 operations; the bound is an explicit Alpha limit,
; not a fake success path.
gfs_copy_user_path:
    ; RDI=NUL-terminated user path.  Copy <=31 bytes after validating each
    ; byte through the same page-walk used by console_write.
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, gfs_path_buffer
    xor r14d, r14d
.next:
    cmp r14d, 31
    jae .bad
    mov rdi, r12
    mov esi, 1
    call user_span_valid
    test eax, eax
    jz .bad
    mov al, [r12]
    cmp al, 0x2f              ; '/' is outside the single root directory
    je .bad
    cmp al, 0x5c              ; '\\' is outside the single root directory
    je .bad
    mov [r13], al
    inc r12
    inc r13
    inc r14d
    test al, al
    jnz .next
    mov eax, 1
    pop r14
    pop r13
    pop r12
    ret
.bad:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    ret

gfs_read_inode:
    ; RDI=inode number.  RAX returns a validated pointer into the shared
    ; gfs_inode_block buffer, or zero for an empty/corrupt inode.
    cmp rdi, 1
    jb .bad
    cmp rdi, 32
    ja .bad
    dec edi
    mov r9d, edi
    shr edi, 2
    add edi, 3
    mov rsi, gfs_inode_block
    call ata_block_read
    test eax, eax
    jz .bad
    mov rax, gfs_inode_block
    and r9d, 3
    shl r9, 7
    add rax, r9
    cmp dword [rax], 0x324f4e49 ; INO2
    jne .bad
    push rax
    mov rdi, rax
    mov esi, 120
    call gwo_fnv32
    pop rdi
    cmp eax, [rdi + 120]
    jne .bad
    cmp dword [rdi + 16], 8
    ja .bad
    cmp qword [rdi + 8], 0x200000
    ja .bad
    mov rax, rdi
    ret
.bad:
    xor eax, eax
    ret

gfs_dir_read:
    mov edi, 11
    mov rsi, gfs_dir_buffer
    jmp ata_block_read

gfs_file_list_user:
    ; RDI=user buffer, RSI=capacity.  Export only checksummed root names as
    ; NUL-separated strings; a short buffer is an explicit ENOSPC result.
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov rdi, r12
    mov rsi, r13
    call user_span_valid
    test eax, eax
    jz .fault
    call gfs_dir_read
    test eax, eax
    jz .io
    xor r14d, r14d
    xor r15d, r15d
.slot:
    cmp r15d, 8
    jae .done
    mov r9, r15
    shl r9, 6
    add r9, gfs_dir_buffer
    movzx ecx, byte [r9]
    test ecx, ecx
    jz .next
    cmp ecx, 31
    ja .next
    push r9
    mov rdi, r9
    mov esi, 60
    call gwo_fnv32
    pop r9
    cmp eax, [r9 + 60]
    jne .next
    mov eax, r14d
    add eax, ecx
    inc eax
    cmp r13, rax
    jb .space
    mov rdi, r12
    add rdi, r14
    lea rsi, [r9 + 6]
    mov r10d, ecx
    rep movsb
    add r14d, r10d
    mov byte [r12 + r14], 0
    inc r14d
.next:
    inc r15d
    jmp .slot
.done:
    mov rax, r14
    jmp .return
.space:
    mov eax, -28
    jmp .return
.fault:
    mov eax, -14
    jmp .return
.io:
    mov eax, -5
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

gfs_dir_lookup:
    ; gfs_path_buffer is a validated NUL-terminated name.  RAX returns the
    ; inode number, or zero; EDX returns the directory slot or 0xff.
    call gfs_dir_read
    test eax, eax
    jz .bad
    xor r8d, r8d
    mov r11d, 0xff
.entry:
    cmp r8d, 8
    jae .missing
    mov r9, r8
    shl r9, 6
    add r9, gfs_dir_buffer
    movzx ecx, byte [r9]
    test ecx, ecx
    jnz .entry_nonempty
    cmp r11d, 0xff
    jne .next
    mov r11d, r8d
    jmp .next
.entry_nonempty:
    cmp ecx, 31
    ja .next
    push r8
    push r9
    mov rdi, r9
    mov esi, 60
    call gwo_fnv32
    pop r9
    pop r8
    cmp eax, [r9 + 60]
    jne .next
    xor edx, edx
.compare:
    cmp edx, ecx
    jae .name_done
    mov al, [r9 + 6 + rdx]
    cmp al, [gfs_path_buffer + rdx]
    jne .next
    inc edx
    jmp .compare
.name_done:
    cmp byte [gfs_path_buffer + rdx], 0
    jne .next
    mov eax, [r9 + 2]
    mov edx, r8d
    ret
.next:
    inc r8d
    jmp .entry
.missing:
    xor eax, eax
    mov edx, r11d
    ret
.bad:
    xor eax, eax
    mov edx, 0xff
    ret

gfs_inode_block_for:
    ; RDI=inode number -> EAX=relative inode block, RDX=byte offset.
    dec edi
    mov eax, edi
    shr eax, 2
    add eax, 3
    and edi, 3
    shl edi, 7
    mov edx, edi
    ret

gfs_commit_super:
    ; Commit the already-updated metadata through the inactive superblock.
    mov rdi, gfs_super_buffer
    mov rax, [rdi + 8]
    inc rax
    mov [rdi + 8], rax
    mov esi, 52
    call gwo_fnv32
    mov [abs gfs_super_buffer + 52], eax
    movzx edi, byte [abs gfs_active_super]
    xor edi, 1
    mov rsi, gfs_super_buffer
    call ata_block_write
    test eax, eax
    jz .bad
    movzx eax, byte [abs gfs_active_super]
    xor eax, 1
    mov [abs gfs_active_super], al
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

gfs_inode_encode_empty:
    ; RDI=inode number, RSI=type (regular file=1).  Creates an empty INO2
    ; record in its table block; callers commit the block afterward.
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov rdi, r12
    call gfs_inode_block_for
    mov r14d, eax
    mov r15d, edx
    mov edi, r14d
    mov rsi, gfs_inode_block
    call ata_block_read
    test eax, eax
    jz .bad
    lea rdi, [gfs_inode_block + r15]
    xor eax, eax
    mov ecx, 16
    rep stosq
    mov dword [gfs_inode_block + r15], 0x324f4e49
    mov word [gfs_inode_block + r15 + 4], r13w
    mov word [gfs_inode_block + r15 + 6], 0644
    mov dword [gfs_inode_block + r15 + 16], 0
    mov rdi, gfs_inode_block
    add rdi, r15
    mov esi, 120
    call gwo_fnv32
    mov [gfs_inode_block + r15 + 120], eax
    mov edi, r14d
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .bad
    mov eax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.bad:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    ret

gfs_create_path:
    ; gfs_path_buffer is populated.  Return inode number or a negative errno.
    call gfs_dir_lookup
    test eax, eax
    jnz .exists
    mov r12d, edx
    cmp r12d, 8
    jae .no_space
    xor r13d, r13d
    mov r14d, 2
.find_inode:
    cmp r14d, 32
    ja .no_space
    mov edi, r14d
    call gfs_read_inode
    test rax, rax
    jz .inode_found
    inc r14d
    jmp .find_inode
.inode_found:
    mov edi, r14d
    mov esi, 1
    call gfs_inode_encode_empty
    test eax, eax
    jnz .inode_ok
    mov al, 'i'
    out 0xe9, al
    jmp .io
.inode_ok:
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jnz .bitmap_ok
    mov al, 'b'
    out 0xe9, al
    jmp .io
.bitmap_ok:
    ; Directory record: name length, flags, inode, name, checksum.
    mov rdi, gfs_dir_buffer
    add rdi, r12
    imul r12, 64
    mov rdi, gfs_dir_buffer
    add rdi, r12
    xor eax, eax
    mov ecx, 8
    rep stosq
    mov rdi, gfs_path_buffer
    xor ecx, ecx
.path_len:
    cmp ecx, 31
    jae .io
    cmp byte [rdi + rcx], 0
    je .path_len_done
    inc ecx
    jmp .path_len
.path_len_done:
    mov rdi, gfs_dir_buffer
    add rdi, r12
    mov [rdi], cl
    mov byte [rdi + 1], 0
    mov dword [rdi + 2], r14d
    mov rsi, gfs_path_buffer
    lea rdi, [rdi + 6]
    mov edx, ecx
    rep movsb
    mov rdi, gfs_dir_buffer
    add rdi, r12
    mov esi, 60
    call gwo_fnv32
    mov [gfs_dir_buffer + r12 + 60], eax
    mov edi, 11
    mov rsi, gfs_dir_buffer
    call ata_block_write
    test eax, eax
    jnz .dir_ok
    mov al, 'd'
    out 0xe9, al
    jmp .io
.dir_ok:
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
.bitmap_write_ok:
    call gfs_commit_super
    test eax, eax
    jz .io
.commit_ok:
    mov eax, r14d
    ret
.exists:
    mov eax, -17
    ret
.no_space:
    mov eax, -28
    ret
.io:
    mov eax, -5
    ret
gfs_file_read_user:
    ; RDI=handle, RSI=user buffer, RDX=count.  Reads are sequential and may
    ; cross the bounded contiguous extent in 512-byte ATA chunks.
    cmp rdi, 1
    jne .bad_handle
    mov r12, [abs current_process]
    mov r13, rsi
    mov r14, rdx
    test r14, r14
    jz .zero
    cmp r14, GFS_MAX_FILE_BYTES
    ja .invalid
    mov rax, [r12 + PROC_OFFSET]
    mov r15, rax
    mov rdi, [r12 + PROC_INODE]
    call gfs_read_inode
    test rax, rax
    jnz .inode_read_ok
    jmp .io
.inode_read_ok:
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov r8, [rbx + 8]
    cmp r15, r8
    jae .zero
    sub r8, r15
    cmp r14, r8
    jbe .count_ready
    mov r14, r8
.count_ready:
    test r14, r14
    jz .zero
    cmp dword [rbx + 16], 1
    jne .io
    mov rdi, r13
    mov rsi, r14
    call user_span_valid
    test eax, eax
    jz .fault
    xor r11d, r11d
.read_block:
    cmp r11d, r14d
    jae .read_done
    mov rax, r15
    add rax, r11
    mov rcx, rax
    shr rax, 9
    cmp rax, [rbx + 32]
    jae .io
    add rax, [rbx + 24]
    mov rdi, rax
    mov rsi, gfs_data_buffer
    call ata_block_read
    test eax, eax
    jz .io
    mov rax, r15
    add rax, r11
    mov edx, eax
    and edx, 511
    mov ecx, 512
    sub ecx, edx
    mov eax, r14d
    sub eax, r11d
    cmp eax, ecx
    jae .read_chunk_ready
    mov ecx, eax
.read_chunk_ready:
    mov r8d, ecx
    mov rsi, gfs_data_buffer
    add rsi, rdx
    mov rdi, r13
    add rdi, r11
    rep movsb
    add r11d, r8d
    jmp .read_block
.read_done:
    add [r12 + PROC_OFFSET], r14
    mov rax, r14
    ret
.zero:
    xor eax, eax
    ret
.bad_handle:
    mov eax, -9
    ret
.invalid:
    mov eax, -22
    ret
.fault:
    mov eax, -14
    ret
.io:
    mov eax, -5
    ret

gfs_file_write_user:
    ; RDI=handle, RSI=user bytes, RDX=count.  Replace the file with one
    ; contiguous extent of bounded ATA blocks.  User bytes are copied and
    ; flushed a block at a time before the inode/bitmap/superblock commit.
    cmp rdi, 1
    jne .bad_handle
    mov r12, [abs current_process]
    mov r13, rsi
    mov r14, rdx
    cmp r14, GFS_MAX_FILE_BYTES
    ja .invalid
    cmp qword [r12 + PROC_OFFSET], 0
    jne .invalid
    mov rdi, r13
    mov rsi, r14
    call user_span_valid
    test eax, eax
    jz .fault
    mov edi, [r12 + PROC_INODE]
    call gfs_read_inode
    test rax, rax
    jz .io
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jz .io
    ; Release every block in the previous extent.
    cmp dword [rbx + 16], 1
    jne .allocate
    mov r10d, [rbx + 32]
    mov r11d, [rbx + 24]
.release_block:
    test r10d, r10d
    jz .allocate
    mov eax, r11d
    mov edx, eax
    shr edx, 3
    mov r9d, edx
    movzx r8d, byte [gfs_bitmap_buffer + r9]
    mov edx, eax
    and edx, 7
    mov ecx, edx
    mov eax, 1
    shl eax, cl
    not al
    and r8b, al
    mov [gfs_bitmap_buffer + r9], r8b
    inc r11d
    dec r10d
    jmp .release_block
.allocate:
    mov eax, r14d
    add eax, 511
    shr eax, 9
    mov [abs gfs_io_blocks], eax
    test eax, eax
    jz .truncate
    mov r15d, 12
.find_extent:
    cmp r15d, [abs gfs_total_blocks]
    jae .no_space
    xor r8d, r8d
.check_extent:
    cmp r8d, [abs gfs_io_blocks]
    jae .extent_found
    mov eax, r15d
    add eax, r8d
    cmp eax, [abs gfs_total_blocks]
    jae .next_extent
    mov ecx, eax
    shr ecx, 3
    movzx edx, byte [gfs_bitmap_buffer + rcx]
    mov ecx, eax
    and ecx, 7
    bt edx, ecx
    jc .next_extent
    inc r8d
    jmp .check_extent
.next_extent:
    inc r15d
    jmp .find_extent
.extent_found:
    mov [abs gfs_io_start], r15d
    xor r10d, r10d
.mark_extent:
    cmp r10d, [abs gfs_io_blocks]
    jae .write_extent
    mov eax, r15d
    add eax, r10d
    mov ecx, eax
    shr ecx, 3
    mov r9d, ecx
    mov edx, eax
    and edx, 7
    mov ecx, edx
    mov eax, 1
    shl eax, cl
    or byte [gfs_bitmap_buffer + r9], al
    inc r10d
    jmp .mark_extent
.write_extent:
    xor r15d, r15d
.write_block:
    cmp r15d, [abs gfs_io_blocks]
    jae .update_inode
    mov eax, r15d
    shl eax, 9
    mov edx, r14d
    sub edx, eax
    cmp edx, 512
    jbe .write_chunk_ready
    mov edx, 512
.write_chunk_ready:
    mov rdi, gfs_data_buffer
    xor eax, eax
    mov ecx, 64
    rep stosq
    mov rsi, r13
    mov eax, r15d
    shl eax, 9
    add rsi, rax
    mov ecx, edx
    mov rdi, gfs_data_buffer
    rep movsb
    mov eax, [abs gfs_io_start]
    add eax, r15d
    mov edi, eax
    mov rsi, gfs_data_buffer
    call ata_block_write
    test eax, eax
    jz .io
    inc r15d
    jmp .write_block
.update_inode:
    mov [rbx + 8], r14
    test r14, r14
    jz .empty_extent
    mov dword [rbx + 16], 1
    mov eax, [abs gfs_io_start]
    mov [rbx + 24], eax
    mov eax, [abs gfs_io_blocks]
    mov [rbx + 32], eax
    jmp .inode_checksum
.empty_extent:
    mov dword [rbx + 16], 0
    mov qword [rbx + 24], 0
    mov dword [rbx + 32], 0
.inode_checksum:
    mov rdi, rbx
    mov esi, 120
    call gwo_fnv32
    mov [rbx + 120], eax
    mov rdi, [r12 + PROC_INODE]
    call gfs_inode_block_for
    mov edi, eax
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
    call gfs_commit_super
    test eax, eax
    jz .io
    mov [r12 + PROC_FILE_SIZE], r14
    mov [r12 + PROC_OFFSET], r14
    mov rax, r14
    ret
.truncate:
    ; A zero-length write is a real truncate.  The old extent has already
    ; been cleared in the in-memory bitmap, so ENOSPC cannot destroy the
    ; previous file and the metadata commit follows the same checked path.
    mov qword [rbx + 8], 0
    mov dword [rbx + 16], 0
    mov qword [rbx + 24], 0
    mov dword [rbx + 32], 0
    mov rdi, rbx
    mov esi, 120
    call gwo_fnv32
    mov [rbx + 120], eax
    mov rdi, [r12 + PROC_INODE]
    call gfs_inode_block_for
    mov edi, eax
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
    call gfs_commit_super
    test eax, eax
    jz .io
    mov qword [r12 + PROC_FILE_SIZE], 0
    mov qword [r12 + PROC_OFFSET], 0
    xor eax, eax
    ret
.bad_handle:
    mov eax, -9
    ret
.invalid:
    mov eax, -22
    ret
.fault:
    mov eax, -14
    ret
.no_space:
    mov eax, -28
    ret
.io:
    mov eax, -5
    ret

gfs_replace_file_kernel:
    ; RDI=inode, RSI=kernel source, RDX=size.  Shared metadata transaction for
    ; the recovery shell and the syscall path; caller has already performed any
    ; user-range validation required by its ABI.
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp r14, 512
    ja .invalid
    mov rdi, r12
    call gfs_read_inode
    test rax, rax
    jz .io
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jz .io
    cmp dword [rbx + 16], 1
    jne .allocate
    mov edx, [rbx + 24]
    mov ecx, edx
    shr ecx, 3
    mov r8d, ecx
    movzx eax, byte [gfs_bitmap_buffer + rcx]
    mov ecx, edx
    and ecx, 7
    mov edx, 1
    shl edx, cl
    not dl
    and al, dl
    mov [gfs_bitmap_buffer + r8], al
.allocate:
    xor r15d, r15d
    test r14, r14
    jz .update
    mov r15d, 12
.find:
    cmp r15d, [abs gfs_total_blocks]
    jae .no_space
    mov eax, r15d
    mov ecx, eax
    shr ecx, 3
    movzx edx, byte [gfs_bitmap_buffer + rcx]
    mov ecx, r15d
    and ecx, 7
    bt edx, ecx
    jc .next
    mov eax, 1
    shl eax, cl
    mov ecx, r15d
    shr ecx, 3
    or byte [gfs_bitmap_buffer + rcx], al
    mov rdi, gfs_data_buffer
    mov rsi, r13
    mov rcx, r14
    rep movsb
    mov edi, r15d
    mov rsi, gfs_data_buffer
    call ata_block_write
    test eax, eax
    jz .io
    jmp .update
.next:
    inc r15d
    jmp .find
.update:
    mov [rbx + 8], r14
    test r14, r14
    jz .empty
    mov dword [rbx + 16], 1
    mov [rbx + 24], r15
    mov dword [rbx + 32], 1
    jmp .checksum
.empty:
    mov dword [rbx + 16], 0
    mov qword [rbx + 24], 0
    mov dword [rbx + 32], 0
.checksum:
    mov rdi, rbx
    mov esi, 120
    call gwo_fnv32
    mov [rbx + 120], eax
    mov rdi, r12
    call gfs_inode_block_for
    mov edi, eax
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
    call gfs_commit_super
    test eax, eax
    jz .io
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.invalid:
    mov eax, -22
    jmp .return
.no_space:
    mov eax, -28
    jmp .return
.io:
    mov eax, -5
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

gfs_shell_name_copy:
    mov rsi, gfs_shell_name
    mov rdi, gfs_path_buffer
    mov ecx, gfs_shell_name_end - gfs_shell_name
    rep movsb
    ret

gfs_shell_save:
    call gfs_shell_name_copy
    call gfs_dir_lookup
    test eax, eax
    jnz .have_inode
    call gfs_create_path
    test eax, eax
    js .fail
.have_inode:
    mov edi, eax
    mov rsi, gfs_shell_source
    mov edx, gfs_shell_source_end - gfs_shell_source
    call gfs_replace_file_kernel
    test eax, eax
    js .fail
    mov rsi, shell_save_ok
    call console_write_string
    ret
.fail:
    mov rsi, shell_unknown
    call console_write_string
    ret

gfs_shell_ls:
    call gfs_dir_read
    test eax, eax
    jz .fail
    xor r12d, r12d
.entry:
    cmp r12d, 8
    jae .done
    mov r9, r12
    shl r9, 6
    add r9, gfs_dir_buffer
    movzx ecx, byte [r9]
    test ecx, ecx
    jz .next
    cmp ecx, 31
    ja .next
    mov rsi, r9
    mov rdi, r9
    mov esi, 60
    call gwo_fnv32
    cmp eax, [r9 + 60]
    jne .next
    movzx ecx, byte [r9]
    lea rsi, [r9 + 6]
    call console_write_bytes
    mov rsi, shell_line_end
    call console_write_string
.next:
    inc r12d
    jmp .entry
.done:
    ret
.fail:
    mov rsi, shell_unknown
    call console_write_string
    ret

gfs_shell_cat:
    call gfs_shell_name_copy
    call gfs_dir_lookup
    test eax, eax
    jz .fail
    mov edi, eax
    call gfs_read_inode
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .fail
    cmp qword [rbx + 8], 512
    ja .fail
    cmp dword [rbx + 16], 1
    jne .empty
    mov rdi, [rbx + 24]
    mov rsi, gfs_data_buffer
    call ata_block_read
    test eax, eax
    jz .fail
    mov ecx, [rbx + 8]
    mov rsi, gfs_data_buffer
    call console_write_bytes
.empty:
    mov rsi, shell_line_end
    call console_write_string
    ret
.fail:
    mov rsi, shell_unknown
    call console_write_string
    ret
.invalid:
    mov eax, -22
    jmp .return
.no_space:
    mov eax, -28
    jmp .return
.io:
    mov eax, -5
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

gfs_file_open_user:
    ; RDI=user path, RSI=reserved flags.  The first handle table is one entry
    ; per process; all handle state is stored in the owned process object.
    mov r12, [abs current_process]
    cmp dword [r12 + PROC_HANDLE], 0
    jne .busy
    call gfs_copy_user_path
    test eax, eax
    jz .fault
    call gfs_dir_lookup
    test eax, eax
    jz .missing
    mov r13d, eax
    mov edi, eax
    call gfs_read_inode
    test rax, rax
    jz .io
    cmp word [rax + 4], 1
    jne .io
    mov dword [r12 + PROC_HANDLE], 1
%if RESOURCE_TEST
    inc dword [abs resource_test_handles_live]
%endif
    mov dword [r12 + PROC_INODE], r13d
    mov qword [r12 + PROC_OFFSET], 0
    mov rax, [rax + 8]
    mov [r12 + PROC_FILE_SIZE], rax
    mov eax, 1
    ret
.busy:
    mov eax, -16
    ret
.missing:
    mov eax, -2
    ret
.fault:
    mov eax, -14
    ret
.io:
    mov eax, -5
    ret

gfs_file_close_user:
    cmp rdi, 1
    jne .bad
    mov r12, [abs current_process]
    cmp dword [r12 + PROC_HANDLE], 0
    je .done
%if RESOURCE_TEST
    dec dword [abs resource_test_handles_live]
%endif
    mov dword [r12 + PROC_HANDLE], 0
    mov qword [r12 + PROC_OFFSET], 0
    mov qword [r12 + PROC_INODE], 0
.done:
    mov eax, 0
    ret
.bad:
    mov eax, -9
    ret

gfs_file_stat_user:
    ; RDI=handle, RSI=user stat buffer (size u64, mode u32, reserved u32).
    cmp rdi, 1
    jne .bad
    mov r12, [abs current_process]
    mov rdi, rsi
    mov esi, 16
    call user_span_valid
    test eax, eax
    jz .fault
    mov edi, [r12 + PROC_INODE]
    call gfs_read_inode
    test rax, rax
    jz .io
    mov r13, rax
    mov rdi, rsi
    mov rax, [r13 + 8]
    mov [rdi], rax
    movzx eax, word [r13 + 6]
    mov [rdi + 8], eax
    mov dword [rdi + 12], 0
    xor eax, eax
    ret
.bad:
    mov eax, -9
    ret
.fault:
    mov eax, -14
    ret
.io:
    mov eax, -5
    ret

gfs_path_create_user:
    ; RDI=user path.  Create a regular empty INO2 record and return its handle.
    mov r12, [abs current_process]
    cmp dword [r12 + PROC_HANDLE], 0
    jne .busy
    call gfs_copy_user_path
    test eax, eax
    jz .fault
    call gfs_create_path
    ; gfs_create_path uses r12-r14 for its directory/inode transaction.
    ; Reload the process object before publishing the new handle state.
    mov r12, [abs current_process]
    test eax, eax
    js .return_error
    mov r13d, eax
    mov dword [r12 + PROC_HANDLE], 1
%if RESOURCE_TEST
    inc dword [abs resource_test_handles_live]
%endif
    mov dword [r12 + PROC_INODE], r13d
    mov qword [r12 + PROC_OFFSET], 0
    mov qword [r12 + PROC_FILE_SIZE], 0
    mov eax, 1
    ret
.return_error:
    ret
.busy:
    mov eax, -16
    ret
.fault:
    mov eax, -14
    ret

gfs_file_unlink_user:
    ; RDI=user path.  Alpha v1 unlinks one regular root entry with the same
    ; checked inode/bitmap/directory/superblock transaction as the host tool.
    mov r12, [abs current_process]
    cmp dword [r12 + PROC_HANDLE], 0
    jne .busy
    call gfs_copy_user_path
    test eax, eax
    jz .fault
    call gfs_dir_lookup
    test eax, eax
    jz .missing
    mov r13d, eax
    mov r14d, edx
    cmp r13d, 1
    je .protected
    mov edi, r13d
    call gfs_read_inode
    test rax, rax
    jz .io
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jz .io
    cmp dword [rbx + 16], 1
    jne .clear_inode
    mov rdx, [rbx + 24]
    cmp rdx, 12
    jb .io
    mov r10d, [rbx + 32]
    mov eax, edx
    add eax, r10d
    cmp eax, [abs gfs_total_blocks]
    jae .io
    mov r11d, edx
.unlink_extent_block:
    test r10d, r10d
    jz .clear_inode
    mov eax, r11d
    mov edx, eax
    shr edx, 3
    mov r8d, edx
    movzx r9d, byte [gfs_bitmap_buffer + r8]
    mov edx, eax
    and edx, 7
    mov eax, 1
    mov ecx, edx
    shl eax, cl
    not al
    and r9b, al
    mov [gfs_bitmap_buffer + r8], r9b
    inc r11d
    dec r10d
    jmp .unlink_extent_block
.clear_inode:
    mov edi, r13d
    call gfs_inode_block_for
    mov r8d, eax
    mov r9d, edx
    lea rdi, [gfs_inode_block + r9]
    xor eax, eax
    mov ecx, 16
    rep stosq
    mov edi, r8d
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .io
    imul r14, 64
    lea rdi, [gfs_dir_buffer + r14]
    xor eax, eax
    mov ecx, 8
    rep stosq
    mov edi, 11
    mov rsi, gfs_dir_buffer
    call ata_block_write
    test eax, eax
    jz .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
    call gfs_commit_super
    test eax, eax
    jz .io
    xor eax, eax
    ret
.busy:
    mov eax, -16
    ret
.fault:
    mov eax, -14
    ret
.missing:
    mov eax, -2
    ret
.protected:
    mov eax, -13
    ret
.io:
    mov eax, -5
    ret
