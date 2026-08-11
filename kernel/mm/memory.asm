physical_memory_seed:
    ; First-MiB is permanently bootstrap/platform-reserved. Collect every
    ; fully-contained 4 KiB page from E820 type-1 ranges in the mapped
    ; 00100000h..003fffffh window. The frame bitmap owns the resulting pool.
    xor edi, edi
    xor ecx, ecx
    mov cx, [abs 0x5ffc]
    mov rsi, 0x6000
.entry:
    test ecx, ecx
    jz .collected
    cmp dword [rsi + 16], 1
    jne .skip_entry
    cmp dword [rsi + 4], 0
    jne .skip_entry
    mov rax, [rsi]
    mov rdx, [rsi + 8]
    test rdx, rdx
    jz .skip_entry
    mov r8, rax
    add r8, rdx
    jc .skip_entry
    cmp r8, 0x400000
    jbe .bounded
    mov r8, 0x400000
.bounded:
    cmp rax, 0x100000
    jae .aligned
    mov rax, 0x100000
.aligned:
    add rax, 0xfff
    and rax, -0x1000
.collect:
    cmp edi, MAX_FRAMES
    jae .collected
    mov rdx, rax
    add rdx, 0x1000
    cmp rdx, r8
    ja .skip_entry
    mov r9, frame_pool
    mov [r9 + rdi * 8], rax
    inc edi
    mov rax, rdx
    jmp .collect
.skip_entry:
    add rsi, 24
    dec ecx
    jmp .entry
.collected:
    cmp edi, 2
    jb .fail
    mov [abs phys_frame_count], edi
    xor edi, edi
    call frame_alloc
    test rax, rax
    jz .fail
    mov [abs phys_first_free], rax
    mov dword [rax], 0x314d5246 ; "FRM1": first owned frame is writable.
    mov rdi, rax
    call frame_alloc
    test rax, rax
    jz .fail
    mov rbx, rax
    mov dword [rbx], 0x324d5246 ; "FRM2": allocator returned a second frame.
    mov rdi, rbx
    call frame_free
    test rax, rax
    jz .fail
    mov al, 'P'
    out 0xe9, al
    mov al, 'M'
    out 0xe9, al
    mov al, 'E'
    out 0xe9, al
    mov al, 'M'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    mov al, '1'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    ret
.skip:
    jmp .skip_entry
.fail:
    cli
.halt: hlt
    jmp .halt

frame_alloc:
    xor ecx, ecx
    mov edx, [abs phys_frame_count]
    mov r8, frame_used
    mov r9, frame_pool
.find:
    cmp ecx, edx
    jae .none
    cmp byte [r8 + rcx], 0
    je .claim
    inc ecx
    jmp .find
.claim:
    mov byte [r8 + rcx], 1
    mov dword [frame_owner + rcx * 4], 0
    mov rax, [r9 + rcx * 8]
    ret
.none:
    xor eax, eax
    ret

frame_free:
    xor ecx, ecx
    mov edx, [abs phys_frame_count]
    mov r8, frame_used
    mov r9, frame_pool
.find_free:
    cmp ecx, edx
    jae .not_found
    cmp [r9 + rcx * 8], rdi
    je .release
    inc ecx
    jmp .find_free
.release:
    cmp byte [r8 + rcx], 1
    jne .not_found
    mov byte [r8 + rcx], 0
    mov dword [frame_owner + rcx * 4], 0
    mov eax, 1
    ret
.not_found:
    xor eax, eax
    ret

; Allocate a frame and attach an explicit owner id.  RDI is the owner id and
; the returned RAX is the physical frame address.  The plain frame_alloc API
; remains available to the kernel bootstrap, but all process-owned frames use
; this path so cross-process frees and double frees are rejected.
frame_alloc_owned:
    push rdi
    call frame_alloc
    test rax, rax
    jz .none
    mov r8, rax
    xor ecx, ecx
    mov edx, [abs phys_frame_count]
.find:
    cmp ecx, edx
    jae .none
    cmp [frame_pool + rcx * 8], r8
    je .store
    inc ecx
    jmp .find
.store:
    mov edx, [rsp]
    mov [frame_owner + rcx * 4], edx
    mov rax, r8
%if RESOURCE_TEST
    inc dword [abs resource_test_frames_live]
%endif
    pop rdi
    ret
.none:
    xor eax, eax
    pop rdi
    ret

; RDI=physical frame, RSI=owner id.  A frame is released only when both the
; allocation bit and owner match.  This is the ownership boundary used by
; address-space teardown and user-fault recovery.
frame_free_owned:
    xor ecx, ecx
    mov edx, [abs phys_frame_count]
.find:
    cmp ecx, edx
    jae .not_found
    cmp [frame_pool + rcx * 8], rdi
    je .check
    inc ecx
    jmp .find
.check:
    cmp byte [frame_used + rcx], 1
    jne .not_found
    cmp [frame_owner + rcx * 4], esi
    jne .not_found
    mov byte [frame_used + rcx], 0
    mov dword [frame_owner + rcx * 4], 0
%if RESOURCE_TEST
    dec dword [abs resource_test_frames_live]
%endif
    mov eax, 1
    ret
.not_found:
    xor eax, eax
    ret

heap_seed:
    ; A fixed-slot reclaiming heap inside the owned physical frame. The first
    ; 16 bytes preserve the FRM1 ownership marker; the bitmap owns 16-byte
    ; slots and heap_free returns them for reuse.
    mov rax, [abs phys_first_free]
    add rax, 16
    mov [abs heap_base], rax
    mov dword [abs heap_slot_count], 255
    mov rdi, 32
    call heap_alloc
    test rax, rax
    jz .fail
    mov dword [rax], 0x31504548 ; "HEP1"
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .fail
    mov dword [rax], 0x32504548 ; "HEP2"
    mov [abs heap_probe_one], rax
    mov rdi, [abs heap_probe_one]
    mov rsi, 64
    call heap_free
    test rax, rax
    jz .fail
    mov rdi, 64
    call heap_alloc
    test rax, rax
    jz .fail
    mov dword [rax], 0x31524648 ; "HFR1": freed slots were reused.
    mov al, 'H'
    out 0xe9, al
    mov al, 'E'
    out 0xe9, al
    mov al, 'A'
    out 0xe9, al
    mov al, 'P'
    out 0xe9, al
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

heap_alloc:
    push rbx
    push r12
    push r13
    mov rax, rdi
    add rax, 15
    jc .none
    shr rax, 4
    test rax, rax
    jz .none
    mov r12, rax
    xor r13d, r13d
.find:
    mov eax, [abs heap_slot_count]
    cmp r13, rax
    jae .none
    xor ebx, ebx
.check:
    cmp rbx, r12
    jae .reserve
    mov rdx, r13
    add rdx, rbx
    cmp rdx, rax
    jae .next
    mov r8, heap_bitmap
    cmp byte [r8 + rdx], 0
    jne .next
    inc rbx
    jmp .check
.next:
    inc r13
    jmp .find
.reserve:
    xor ebx, ebx
.mark:
    cmp rbx, r12
    jae .return
    mov rdx, r13
    add rdx, rbx
    mov r8, heap_bitmap
    mov byte [r8 + rdx], 1
    inc rbx
    jmp .mark
.return:
    mov rax, [abs heap_base]
    mov rdx, r13
    shl rdx, 4
    add rax, rdx
    pop r13
    pop r12
    pop rbx
    ret
.none:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
heap_free:
    push rbx
    push r12
    push r13
    test rdi, rdi
    jz .none
    mov rax, [abs heap_base]
    cmp rdi, rax
    jb .none
    mov rdx, [abs heap_slot_count]
    shl rdx, 4
    add rax, rdx
    cmp rdi, rax
    jae .none
    mov rax, rdi
    sub rax, [abs heap_base]
    test rax, 15
    jnz .none
    shr rax, 4
    mov r13, rax
    mov rax, rsi
    add rax, 15
    jc .none
    shr rax, 4
    test rax, rax
    jz .none
    mov r12, rax
    mov rdx, r13
    add rdx, r12
    cmp rdx, [abs heap_slot_count]
    ja .none
    xor ebx, ebx
.release:
    cmp rbx, r12
    jae .success
    mov rdx, r13
    add rdx, rbx
    mov r8, heap_bitmap
    mov byte [r8 + rdx], 0
    inc rbx
    jmp .release
.success:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
.none:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret
