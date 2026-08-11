gwo_load_user:
    mov rdi, user_gwo_image
    mov esi, user_gwo_image_end - user_gwo_image
    jmp gwo_load_image

gwo_load_image:
    ; GWO2 v2 Alpha has a 32-byte header and one 16-byte bytecode section.
    ; Every size, target, checksum, instruction boundary, import signature,
    ; and stack effect is checked before any user address space is created.
    push r12
    push r13
    mov r12, rdi
    mov r13d, esi
    cmp r13d, 48
    jb .fail
    cmp dword [r12], 0x324f5747 ; GWO2
    jne .fail
    cmp word [r12 + 4], 2
    jne .fail
    cmp word [r12 + 6], 1
    jne .fail
    cmp word [r12 + 8], 1
    jne .fail
    cmp word [r12 + 10], 0
    jne .fail
    cmp dword [r12 + 12], 32
    jne .fail
    cmp dword [r12 + 16], 1
    jne .fail
    mov eax, [r12 + 20]
    mov r8d, [r12 + 24]
    test r8d, r8d
    jz .fail
    cmp eax, r8d
    jae .fail
    mov [abs user_payload_entry], eax
    cmp r8d, MAX_PAYLOAD_BYTES
    ja .fail
    mov eax, r8d
    add eax, 48
    cmp eax, r13d
    jne .fail
    cmp dword [r12 + 32], 1
    jne .fail
    cmp dword [r12 + 36], 48
    jne .fail
    cmp dword [r12 + 40], r8d
    jne .fail
    lea rdi, [r12 + 32]
    mov esi, r8d
    add rsi, 16
    call gwo_fnv32
    cmp eax, [r12 + 28]
    jne .fail
    lea rdi, [r12 + 48]
    mov esi, r8d
    call gwo_fnv32
    cmp eax, [r12 + 44]
    jne .fail
    lea rsi, [r12 + 48]
    mov rdi, user_payload_kernel
    mov ecx, r8d
    rep movsb
    mov [abs user_payload_size], r8d
    mov rdi, user_payload_kernel
    mov esi, r8d
    mov edx, [abs user_payload_entry]
    call gwo2_verify_code
    test eax, eax
    jz .fail
    mov al, 'G'
    out 0xe9, al
    mov al, 'W'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    mov eax, 1
    pop r13
    pop r12
    ret
.fail:
    xor eax, eax
    pop r13
    pop r12
    ret

gwo_fnv32:
    mov eax, 2166136261
.next:
    test rsi, rsi
    jz .done
    movzx edx, byte [rdi]
    xor eax, edx
    imul eax, 16777619
    inc rdi
    dec rsi
    jmp .next
.done:
    ret

gwo2_verify_code:
    ; RDI=bytecode, ESI=bytes.  The verifier uses a bounded instruction map
    ; for both entry and jump-target boundaries, so malformed control flow is
    ; rejected before ring 3 receives a page.
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov rdi, gwo2_boundaries
    xor eax, eax
    mov ecx, MAX_PAYLOAD_BYTES
    rep stosb
    xor r8d, r8d
    mov r11d, 0xff
    xor r9d, r9d
.decode:
    cmp r8d, r13d
    jae .decode_done
    mov byte [gwo2_boundaries + r8], 1
    movzx eax, byte [r12 + r8]
    xor r10d, r10d
    xor r11d, r11d
    cmp eax, 1
    je .const
    cmp eax, 2
    je .local_load
    cmp eax, 3
    je .local_store
    cmp eax, 4
    jb .not_arithmetic
    cmp eax, 9
    jbe .arithmetic
    cmp eax, 22
    je .arithmetic
.not_arithmetic:
    cmp eax, 15
    je .byte_const
    cmp eax, 16
    je .byte_load
    cmp eax, 17
    je .byte_store
    cmp eax, 18
    je .duplicate
    cmp eax, 19
    je .drop
    cmp eax, 10
    je .jump
    cmp eax, 11
    je .jump_zero
    cmp eax, 12
    je .import
    cmp eax, 13
    je .return
    cmp eax, 14
    je .halt
    cmp eax, 20
    je .call
    cmp eax, 21
    je .return_void
    cmp eax, 22
    je .arithmetic
    jmp .bad
.const:
    mov r10d, 5
    mov r11d, 1
    jmp .finish
.local_load:
    mov r10d, 2
    movzx edx, byte [r12 + r8 + 1]
    cmp edx, 255
    jae .bad
    mov r11d, 1
    jmp .finish
.local_store:
    mov r10d, 2
    movzx edx, byte [r12 + r8 + 1]
    cmp edx, 255
    jae .bad
    mov r11d, -1
    jmp .finish
.arithmetic:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.byte_const:
    movzx edx, byte [r12 + r8 + 1]
    lea r10d, [edx + 2]
    mov r11d, 1
    jmp .finish
.byte_load:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.byte_store:
    mov r10d, 1
    mov r11d, -3
    jmp .finish
.duplicate:
    mov r10d, 1
    mov r11d, 1
    jmp .finish
.drop:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.jump:
    mov r10d, 3
    jmp .finish
.jump_zero:
    mov r10d, 3
    mov r11d, -1
    jmp .finish
.import:
    mov r10d, 3
    movzx edx, byte [r12 + r8 + 1]
    movzx ecx, byte [r12 + r8 + 2]
    cmp edx, 1
    je .import_one
    cmp edx, 2
    je .import_one
    cmp edx, 3
    je .import_zero
    cmp edx, 4
    je .import_two_result
    cmp edx, 5
    je .import_two_result
    cmp edx, 6
    je .import_three_result
    cmp edx, 7
    je .import_three_result
    cmp edx, 8
    je .import_one_zero
    cmp edx, 9
    je .import_two_zero
    cmp edx, 10
    je .import_one_zero
    cmp edx, 11
    je .import_one_zero
    cmp edx, 12
    je .import_one_zero
    cmp edx, 13
    je .import_two_void
    cmp edx, 14
    je .import_zero
    cmp edx, 15
    je .import_two_result
    cmp edx, 16
    je .import_one_result
    cmp edx, 17
    je .import_four_result
    cmp edx, 18
    je .import_two_result
    cmp edx, 19
    je .import_two_result
    jmp .bad
.import_one:
    cmp ecx, 1
    jne .bad
    mov r11d, -1
    jmp .finish
.import_zero:
    test ecx, ecx
    jnz .bad
    jmp .finish
.import_two_result:
    cmp ecx, 2
    jne .bad
    mov r11d, -1
    jmp .finish
.import_three_result:
    cmp ecx, 3
    jne .bad
    mov r11d, -2
    jmp .finish
.import_four_result:
    cmp ecx, 4
    jne .bad
    mov r11d, -3
    jmp .finish
.import_one_zero:
    cmp ecx, 1
    jne .bad
    jmp .finish
.import_two_zero:
    cmp ecx, 2
    jne .bad
    mov r11d, -1
    jmp .finish
.import_two_void:
    cmp ecx, 2
    jne .bad
    mov r11d, -2
    jmp .finish
.import_one_result:
    cmp ecx, 1
    jne .bad
    xor r11d, r11d
    jmp .finish
.return:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.halt:
    mov r10d, 1
.return_void:
    mov r10d, 1
    jmp .finish
.call:
    mov r10d, 5
    movzx edx, byte [r12 + r8 + 3]
    movzx ecx, byte [r12 + r8 + 4]
    cmp edx, 255
    ja .bad
    cmp ecx, 1
    ja .bad
    mov r11d, ecx
    sub r11d, edx
.finish:
    mov eax, r8d
    add eax, r10d
    jc .bad
    cmp eax, r13d
    ja .bad
    cmp byte [r12 + r8], 10
    je .check_jump_bounds
    cmp byte [r12 + r8], 11
    jne .advance
.check_jump_bounds:
    movsx edx, word [r12 + r8 + 1]
    lea rcx, [r8 + r10]
    add ecx, edx
    js .bad
    cmp ecx, r13d
    jae .bad
.advance:
    add r8d, r10d
    jmp .decode
.decode_done:
    ; Re-decode only to validate that every jump lands on a marked boundary.
    xor r8d, r8d
.boundaries:
    cmp r8d, r13d
    jae .ok
    movzx eax, byte [r12 + r8]
    mov r10d, 1
    cmp eax, 1
    je .boundary_const
    cmp eax, 2
    je .boundary_length2
    cmp eax, 3
    je .boundary_length2
    cmp eax, 15
    je .boundary_byte_const
    cmp eax, 16
    je .boundary_length
    cmp eax, 17
    je .boundary_length
    cmp eax, 18
    je .boundary_length
    cmp eax, 19
    je .boundary_length
    cmp eax, 10
    je .boundary_jump
    cmp eax, 11
    je .boundary_jump
    cmp eax, 12
    je .boundary_jump
    cmp eax, 13
    je .boundary_length
    cmp eax, 14
    je .boundary_length
    cmp eax, 20
    je .boundary_call
    cmp eax, 21
    je .boundary_length
    cmp eax, 22
    je .boundary_length
    cmp eax, 4
    jb .bad
    cmp eax, 9
    ja .bad
    jmp .boundary_length
.boundary_length2:
    mov r10d, 2
    jmp .boundary_length
.boundary_const:
    mov r10d, 5
    jmp .boundary_length
.boundary_byte_const:
    movzx r10d, byte [r12 + r8 + 1]
    add r10d, 2
    jmp .boundary_length
.boundary_call:
    mov r10d, 5
    movzx ecx, word [r12 + r8 + 1]
    cmp ecx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rcx], 1
    jne .bad
    jmp .boundary_length
.boundary_jump:
    cmp eax, 12
    je .boundary_import
    mov r10d, 3
    movsx edx, word [r12 + r8 + 1]
    lea rcx, [r8 + r10]
    add ecx, edx
    js .bad
    cmp ecx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rcx], 1
    jne .bad
.boundary_import:
    mov r10d, 3
.boundary_length:
    add r8d, r10d
    jmp .boundaries
.cfg_init:
    ; Re-run the verified instruction map as a small forward data-flow
    ; analysis.  A linear stack counter is insufficient for if/else and loop
    ; joins: every reachable instruction receives exactly one operand depth.
    mov rdi, gwo2_depths
    mov al, 0xff
    mov ecx, MAX_PAYLOAD_BYTES
    rep stosb
    mov edx, [abs user_payload_entry]
    cmp edx, r13d
    jae .bad
    mov byte [gwo2_depths + rdx], 0
.cfg_pass:
    xor r10d, r10d              ; changed in this pass
    xor r8d, r8d
.cfg_scan:
    cmp r8d, r13d
    jae .cfg_done_scan
    movzx eax, byte [gwo2_depths + r8]
    cmp eax, 0xff
    je .cfg_next
    cmp byte [gwo2_boundaries + r8], 1
    jne .bad
    mov r9d, eax                ; input depth
    movzx eax, byte [r12 + r8]
    mov r14d, 1                 ; instruction length
    xor r15d, r15d              ; stack effect
    xor ebx, ebx                ; successor kind: normal/jump/cond/terminal
    cmp eax, 1
    je .cfg_const
    cmp eax, 2
    je .cfg_load_local
    cmp eax, 3
    je .cfg_store_local
    cmp eax, 4
    jb .cfg_special
    cmp eax, 9
    jbe .cfg_arithmetic
    cmp eax, 22
    je .cfg_arithmetic
.cfg_special:
    cmp eax, 10
    je .cfg_jump
    cmp eax, 11
    je .cfg_jump_zero
    cmp eax, 12
    je .cfg_import
    cmp eax, 13
    je .cfg_return
    cmp eax, 14
    je .cfg_halt
    cmp eax, 20
    je .cfg_call
    cmp eax, 21
    je .cfg_return_void
    cmp eax, 15
    je .cfg_byte_const
    cmp eax, 16
    je .cfg_byte_load
    cmp eax, 17
    je .cfg_byte_store
    cmp eax, 18
    je .cfg_duplicate
    cmp eax, 19
    je .cfg_drop
    jmp .bad
.cfg_const:
    mov r14d, 5
    mov r15d, 1
    jmp .cfg_effect
.cfg_load_local:
    mov r14d, 2
    mov r15d, 1
    jmp .cfg_effect
.cfg_store_local:
    mov r14d, 2
    mov r15d, -1
    jmp .cfg_effect
.cfg_arithmetic:
    mov r15d, -1
    jmp .cfg_effect
.cfg_jump:
    mov r14d, 3
    mov ebx, 1
    jmp .cfg_effect
.cfg_jump_zero:
    mov r14d, 3
    mov r15d, -1
    mov ebx, 2
    jmp .cfg_effect
.cfg_return:
    mov r15d, -1
    mov ebx, 3
    jmp .cfg_effect
.cfg_halt:
    mov ebx, 3
    jmp .cfg_effect
.cfg_return_void:
    xor r15d, r15d
    mov ebx, 3
    jmp .cfg_effect
.cfg_call:
    mov r14d, 5
    movzx edx, byte [r12 + r8 + 3]
    movzx ecx, byte [r12 + r8 + 4]
    cmp edx, 255
    ja .bad
    cmp ecx, 1
    ja .bad
    mov r15d, ecx
    sub r15d, edx
    mov ebx, 4
    jmp .cfg_effect
.cfg_byte_const:
    movzx edx, byte [r12 + r8 + 1]
    lea r14d, [edx + 2]
    mov r15d, 1
    jmp .cfg_effect
.cfg_byte_load:
    mov r15d, -1
    jmp .cfg_effect
.cfg_byte_store:
    mov r15d, -3
    jmp .cfg_effect
.cfg_duplicate:
    mov r15d, 1
    jmp .cfg_effect
.cfg_drop:
    mov r15d, -1
    jmp .cfg_effect
.cfg_import:
    mov r14d, 3
    movzx edx, byte [r12 + r8 + 1]
    movzx ecx, byte [r12 + r8 + 2]
    cmp edx, 1
    je .cfg_import_pop
    cmp edx, 2
    je .cfg_import_exit
    cmp edx, 3
    je .cfg_import_zero
    cmp edx, 4
    je .cfg_import_pop
    cmp edx, 5
    je .cfg_import_pop
    cmp edx, 6
    je .cfg_import_pop2
    cmp edx, 7
    je .cfg_import_pop2
    cmp edx, 8
    je .cfg_import_zero
    cmp edx, 9
    je .cfg_import_pop
    cmp edx, 10
    je .cfg_import_zero
    cmp edx, 11
    je .cfg_import_zero
    cmp edx, 12
    je .cfg_import_zero
    cmp edx, 13
    je .cfg_import_pop2
    cmp edx, 14
    je .cfg_import_one_result
    cmp edx, 15
    je .cfg_import_pop
    cmp edx, 16
    je .cfg_import_one_result
    cmp edx, 17
    je .cfg_import_four_result
    cmp edx, 18
    je .cfg_import_pop
    cmp edx, 19
    je .cfg_import_pop
    jmp .bad
.cfg_import_pop:
    mov r15d, -1
    jmp .cfg_effect
.cfg_import_pop2:
    mov r15d, -2
    jmp .cfg_effect
.cfg_import_four_result:
    mov r15d, -3
    jmp .cfg_effect
.cfg_import_zero:
    xor r15d, r15d
    jmp .cfg_effect
.cfg_import_one_result:
    mov r15d, 1
    jmp .cfg_effect
.cfg_import_exit:
    mov r15d, -1
    mov ebx, 3
.cfg_effect:
    mov edx, r9d
    add edx, r15d
    js .bad
    cmp edx, 192
    ja .bad
    mov r9d, edx                ; output depth
    ; Merge the fall-through successor for normal and conditional ops.
    cmp ebx, 1
    je .cfg_target
    cmp ebx, 3
    je .cfg_target
    mov edx, r8d
    add edx, r14d
    jc .bad
    cmp edx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rdx], 1
    jne .bad
    movzx ecx, byte [gwo2_depths + rdx]
    cmp ecx, 0xff
    jne .cfg_fall_known
    mov [gwo2_depths + rdx], r9b
    mov r10d, 1
    jmp .cfg_target
.cfg_fall_known:
    cmp ecx, r9d
    jne .bad
.cfg_target:
    ; Unconditional and conditional jumps merge their encoded target.
    cmp ebx, 0
    je .cfg_next
    cmp ebx, 3
    je .cfg_next
    cmp ebx, 4
    je .cfg_call_target
    movsx edx, word [r12 + r8 + 1]
    lea ecx, [r8 + r14]
    add ecx, edx
    js .bad
    cmp ecx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rcx], 1
    jne .bad
    movzx edx, byte [gwo2_depths + rcx]
    cmp edx, 0xff
    jne .cfg_target_known
    mov [gwo2_depths + rcx], r9b
    mov r10d, 1
    jmp .cfg_next
.cfg_target_known:
    cmp edx, r9d
    jne .bad
.cfg_call_target:
    movzx ecx, word [r12 + r8 + 1]
    cmp ecx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rcx], 1
    jne .bad
    movzx edx, byte [r12 + r8 + 3]
    movzx eax, byte [gwo2_depths + rcx]
    cmp eax, 0xff
    jne .cfg_call_known
    mov [gwo2_depths + rcx], dl
    mov r10d, 1
    jmp .cfg_next
.cfg_call_known:
    cmp eax, edx
    jne .bad
.cfg_next:
    inc r8d
    jmp .cfg_scan
.cfg_done_scan:
    test r10d, r10d
    jnz .cfg_pass
.ok:
    mov eax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.bad:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
