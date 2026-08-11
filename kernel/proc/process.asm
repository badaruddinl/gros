process_create:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    cmp r15, MAX_PAYLOAD_BYTES
    ja .fail
    xor eax, eax
    mov rdi, r12
    mov ecx, PROC_SIZE / 8
    rep stosq
    ; Publish the owner before the first allocation so a later partial
    ; failure can return every frame without taking the kernel fail-stop path.
    mov dword [r12 + PROC_PID], r13d

%if PROCESS_CREATE_TEST
    ; Validation images arm a one-shot countdown after the two boot processes
    ; exist.  Child attempt 1 fails at allocation 1, attempt 2 at allocation
    ; 2, and so on; an attempt beyond the real allocation count succeeds.
    mov dword [abs process_create_test_active], 0
    cmp dword [abs process_create_test_armed], 0
    je .test_not_child
    inc dword [abs process_create_test_attempt]
    mov dword [abs process_create_test_counter], 0
    mov dword [abs process_create_test_active], 1
    mov al, 'P'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, 'A'
    out 0xe9, al
.test_not_child:
%endif

    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_CR3], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_PDPT], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_PD], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_PT], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_CODE], rax
    mov r8, rax
    mov rdi, r8
    call zero_page

    ; Allocate and map every verified payload page after the fixed native
    ; interpreter page.  The page table is scanned during teardown, so a
    ; compiler artifact may grow without hiding owned frames in a side table.
    mov eax, r15d
    add eax, PAGE_SIZE - 1
    shr eax, 12
    mov [r12 + PROC_PAYLOAD_PAGES], eax
    mov eax, [abs user_payload_entry]
    mov [r12 + PROC_ENTRY], eax
    xor r11d, r11d
.payload_page:
    cmp r11d, [r12 + PROC_PAYLOAD_PAGES]
    jae .payload_done
    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov r10, rax
    mov rdi, r10
    call zero_page
    mov rbx, [r12 + PROC_PT]
    mov eax, r11d
    inc eax
    mov r8, r10
    or r8, 5
    mov [rbx + rax * 8], r8
    mov rdi, r10
    mov rsi, r14
    mov eax, r11d
    shl eax, 12
    add rsi, rax
    mov ecx, PAGE_SIZE
    mov edx, r15d
    sub edx, eax
    cmp edx, PAGE_SIZE
    jae .payload_copy
    mov ecx, edx
.payload_copy:
    rep movsb
    inc r11d
    jmp .payload_page
.payload_done:

    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_STACK], rax
    mov r8, rax
    mov rdi, r8
    call zero_page
    mov rdx, USER_CODE + VM_BLOB_OFFSET
    add rdx, r15
    mov [r8 + 24], rdx
    mov eax, [r12 + PROC_ENTRY]
    mov [r8 + 40], eax

    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_KSTACK], rax

    ; Root -> PDPT -> PD.  Kernel identity leaves stay supervisor-only.
    mov rbx, [r12 + PROC_CR3]
    mov rax, [r12 + PROC_PDPT]
    or rax, 7
    mov [rbx], rax
    mov rbx, [r12 + PROC_PDPT]
    mov rax, [r12 + PROC_PD]
    or rax, 7
    mov [rbx], rax
    mov rbx, [r12 + PROC_PD]
    mov qword [rbx], 0x0083
    mov qword [rbx + 8], 0x200083
    mov rax, [r12 + PROC_PT]
    or rax, 7
    mov [rbx + 16], rax

    ; PTE[0] is the native RX entry, PTE[1..N] are verified RX bytecode,
    ; USER_GUARD remains unmapped, and USER_STACK is the RW runtime stack.
    ; A missing PTE therefore becomes a recoverable user fault.
    mov rbx, [r12 + PROC_PT]
    mov rax, [r12 + PROC_CODE]
    or rax, 5
    mov [rbx], rax
    mov rax, [r12 + PROC_STACK]
    or rax, 7
    mov rcx, USER_STACK
    sub rcx, USER_BASE
    shr rcx, 12
    mov [rbx + rcx * 8], rax

    ; Reserve private VM frame storage after the user stack.  Each frame has
    ; a return record plus 255 local slots; the process heap starts after this
    ; region so user allocations cannot overlap interpreter state.
    xor r11d, r11d
.vm_runtime_page:
    cmp r11d, VM_RUNTIME_PAGES
    jae .vm_runtime_done
    mov rdi, r13
    call process_create_alloc_owned
    test rax, rax
    jz .fail
    mov r10, rax
    mov rdi, r10
    call zero_page
    mov rbx, [r12 + PROC_PT]
    mov eax, r11d
    add eax, (VM_RUNTIME_BASE - USER_BASE) >> 12
    mov r8, r10
    or r8, 7
    mov [rbx + rax * 8], r8
    inc r11d
    jmp .vm_runtime_page
.vm_runtime_done:

    ; The executable page contains the fixed ring-3 GrVM entry followed by
    ; verified GWO2 bytecode.  The VM itself is native bootstrap code; the
    ; program it interprets is always the checked artifact supplied by the
    ; loader, never a source-specific shortcut.
    mov rdi, [r12 + PROC_CODE]
    mov rsi, user_vm_program
    mov ecx, user_vm_program_end - user_vm_program
    rep movsb
    mov dword [r12 + PROC_PID], r13d
    mov dword [r12 + PROC_STATE], PROC_READY
    mov dword [r12 + PROC_EXIT_STATUS], 0
    mov qword [r12 + PROC_RIP], USER_CODE
    mov qword [r12 + PROC_RSP], USER_STACK_TOP
    mov qword [r12 + PROC_FLAGS], 0x202
    mov qword [r12 + PROC_NEXT], 0
    mov qword [r12 + PROC_HEAP], VM_RUNTIME_END

    ; A timer interrupt from ring 3 returns through this prepared full frame.
    mov r8, [r12 + PROC_KSTACK]
    lea r9, [r8 + PAGE_SIZE]
    mov [r12 + PROC_KTOP], r9
    ; Keep the saved iret frame below the deepest syscall call chain.  The
    ; top 160 bytes are live kernel-stack scratch while a process enters via
    ; SYSCALL; placing the persistent frame there would let a return address
    ; overwrite its SS word before the next timer switch.
    sub r9, 512
    mov [r12 + PROC_CONTEXT], r9
    mov rdi, r9
    xor eax, eax
    mov ecx, 20
    rep stosq
    mov qword [r9 + 120], USER_CODE
    mov qword [r9 + 128], 0x33
    mov qword [r9 + 136], 0x202
    mov qword [r9 + 144], USER_STACK_TOP
    mov qword [r9 + 152], 0x2b
%if PROCESS_CREATE_TEST
    cmp dword [abs process_create_test_active], 1
    jne .test_success_done
    mov dword [abs process_create_test_active], 0
    mov al, 'P'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, 'S'
    out 0xe9, al
.test_success_done:
%endif
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
%if PROCESS_CREATE_TEST
    mov dword [abs process_create_test_active], 0
%endif
    mov rdi, r12
    mov rsi, r13
    call process_destroy_partial
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Allocation wrapper used only by process_create.  In a validation image the
; Nth child attempt fails at its Nth allocation exactly once; normal images
; assemble this as a direct tail call with no test state or marker bytes.
process_create_alloc_owned:
%if PROCESS_CREATE_TEST
    cmp dword [abs process_create_test_active], 1
    jne .real
    inc dword [abs process_create_test_counter]
    mov eax, [abs process_create_test_attempt]
    cmp [abs process_create_test_counter], eax
    jne .real
    mov dword [abs process_create_test_active], 0
    mov al, 'P'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    xor eax, eax
    ret
.real:
%endif
    jmp frame_alloc_owned

process_destroy_partial:
    ; RDI=partially initialized process, RSI=owner PID.  Only pages that have
    ; already been installed in the process page table are walked; the fixed
    ; object fields then release the root tables and native frames exactly
    ; once.  This path is used only before the process is published.
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, esi
    mov rbx, [r12 + PROC_PT]
    test rbx, rbx
    jz .frames
    mov eax, USER_STACK
    sub eax, USER_BASE
    shr eax, 12
    mov r14d, 1
.user_page:
    cmp r14d, 512
    jae .frames
    cmp r14d, eax
    je .next_user_page
    mov rdi, [rbx + r14 * 8]
    test rdi, 1
    jz .next_user_page
    and rdi, -PAGE_SIZE
    mov rsi, r13
    call frame_free_owned
    mov qword [rbx + r14 * 8], 0
.next_user_page:
    inc r14d
    jmp .user_page
.frames:
    lea rbx, [r12 + PROC_CR3]
    mov r14d, 7
.frame:
    mov rdi, [rbx]
    test rdi, rdi
    jz .next_frame
    mov rsi, r13
    call frame_free_owned
    mov qword [rbx], 0
.next_frame:
    add rbx, 8
    dec r14d
    jnz .frame
    ; The allocation transaction has not published this process yet.  Return
    ; the object to one canonical reusable state as well as releasing frames;
    ; otherwise a later spawn observes state zero and reports a permanent
    ; EBUSY after a single -ENOMEM failure.
    mov rdi, r12
    xor eax, eax
    mov ecx, PROC_SIZE / 8
    rep stosq
    mov dword [r12 + PROC_STATE], PROC_EXITED
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

process_map_page:
    ; RDI=process, RSI=page-aligned user virtual address.  The page is
    ; allocated with the process pid as owner and becomes a writable user PTE.
    push rbx
    push r12
    mov r12, rdi
    cmp rsi, USER_BASE
    jb .fail
    cmp rsi, USER_LIMIT - PAGE_SIZE
    ja .fail
    mov rbx, [r12 + PROC_PT]
    mov rax, rsi
    sub rax, USER_BASE
    shr rax, 12
    cmp rax, 512
    jae .fail
    mov r10, rax
    test qword [rbx + rax * 8], 1
    jnz .present
    mov rdi, [r12 + PROC_PID]
    call frame_alloc_owned
    test rax, rax
    jz .fail
    mov r8, rax
    mov rdi, r8
    call zero_page
    mov rax, r8
    or rax, 7
    mov [rbx + r10 * 8], rax
.present:
    mov eax, 1
    pop r12
    pop rbx
    ret
.fail:
    xor eax, eax
    pop r12
    pop rbx
    ret

process_reap:
    ; RDI=exited process.  Reclaim every frame whose owner is the process id.
    ; The function runs only after the scheduler has selected a different
    ; context, so freeing the old kernel stack cannot invalidate the caller.
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, [r12 + PROC_PID]
    ; Reclaim all user mappings except the fixed stack page.  This covers the
    ; payload span and any heap pages created by mem_grow without permitting a
    ; process to release another process's frames.
    mov rbx, [r12 + PROC_PT]
    mov eax, USER_STACK
    sub eax, USER_BASE
    shr eax, 12
    mov r14d, 1
.user_page:
    cmp r14d, 512
    jae .user_pages_done
    cmp r14d, eax
    je .user_page_next
    mov rdi, [rbx + r14 * 8]
    test rdi, 1
    jz .user_page_next
    and rdi, -PAGE_SIZE
    mov rsi, r13
    call frame_free_owned
    mov qword [rbx + r14 * 8], 0
.user_page_next:
    inc r14d
    jmp .user_page
.user_pages_done:
    lea rbx, [r12 + PROC_CR3]
    mov r14d, 7
.frame:
    mov rdi, [rbx]
    test rdi, rdi
    jz .next
    mov rsi, r13
    call frame_free_owned
    mov qword [rbx], 0
.next:
    add rbx, 8
    dec r14d
    jnz .frame
%if RESOURCE_TEST
    cmp dword [r12 + PROC_HANDLE], 0
    je .handle_done
    dec dword [abs resource_test_handles_live]
.handle_done:
%endif
    mov dword [r12 + PROC_STATE], PROC_EXITED
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%if RESOURCE_TEST
; Emit a stable per-reap resource snapshot. R<frames>H<handles>P<pid> lets a
; failed validation identify the reaped owner without adding a test syscall.
resource_test_emit_snapshot:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    mov rsi, rdi
    mov al, 'R'
    out 0xe9, al
    mov eax, [abs resource_test_frames_live]
    call resource_test_emit_hex32
    mov al, 'H'
    out 0xe9, al
    mov eax, [abs resource_test_handles_live]
    call resource_test_emit_hex32
    mov al, 'P'
    out 0xe9, al
    mov eax, [rsi + PROC_PID]
    call resource_test_emit_hex32
    mov al, 10
    out 0xe9, al
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

resource_test_emit_hex32:
    push rbx
    push rcx
    push rdx
    mov ebx, eax
    mov ecx, 8
.hex:
    mov edx, ebx
    shr edx, 28
    mov al, [resource_test_hex + rdx]
    out 0xe9, al
    shl ebx, 4
    dec ecx
    jnz .hex
    pop rdx
    pop rcx
    pop rbx
    ret
%endif

interrupt_controller_seed:
    ; Remap the legacy PIC so IRQ0/IRQ1 use the installed x86_64 IDT gates.
    mov al, 0x11
    out 0x20, al
    out 0xa0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xa1, al
    mov al, 4
    out 0x21, al
    mov al, 2
    out 0xa1, al
    mov al, 1
    out 0x21, al
    out 0xa1, al
    mov al, 0xfc                 ; unmask timer and keyboard on the master
    out 0x21, al
    mov al, 0xff                 ; no slave IRQs in this bootstrap profile
    out 0xa1, al

    ; PIT channel 0, mode 3, approximately 18 Hz (1193182 / 0xffff).
    mov al, 0x36
    out 0x43, al
    mov al, 0xff
    out 0x40, al
    mov al, 0xff
    out 0x40, al
    ret

syscall_seed:
    ; Configure the bounded 64-bit syscall ABI. STAR selects the existing
    ; kernel code/data pair (18h/20h) and the DPL3 pair (33h/2bh); LSTAR
    ; enters syscall_entry and FMASK keeps interrupts disabled in the handler.
    mov ecx, 0xc0000080
    rdmsr
    or eax, 1                  ; EFER.SCE
    wrmsr
    mov ecx, 0xc0000081
    xor eax, eax
    mov edx, 0x00200018        ; SYSRET base = 20h, SYSCALL CS = 18h
    wrmsr
    mov ecx, 0xc0000082
    mov rax, syscall_entry
    mov rdx, rax
    shr rdx, 32
    wrmsr
    mov ecx, 0xc0000084
    mov eax, 0x200             ; mask IF on kernel entry
    xor edx, edx
    wrmsr
    mov al, 'S'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    mov al, 'G'
    out 0xe9, al
    ret

user_mode_seed:
    ; Validate the GWO2 bytecode image, construct two independently owned
    ; address spaces, and enter PID 1 through SYSRET.  PID 2 is already ready
    ; on the run queue, so a timer or an exit can switch to it without copying
    ; user memory or reusing a page table.
    cli
    call gwo_load_user
    test eax, eax
    jz .load_fail
    mov rdx, user_payload_kernel
    mov ecx, [abs user_payload_size]
    mov rdi, process_one
    mov rsi, 1
    call process_create
    mov qword [abs process_one + PROC_ARG_PTR], process_one_args
    mov qword [abs process_one + PROC_ARG_LEN], 0
    mov rdi, user_helper_image
    mov esi, user_helper_image_end - user_helper_image
    call gwo_load_image
    mov rdx, user_payload_kernel
    mov ecx, [abs user_payload_size]
    mov rdi, process_two
    mov rsi, 2
    call process_create
    mov qword [abs process_two + PROC_ARG_PTR], process_two_args
    mov qword [abs process_two + PROC_ARG_LEN], 0
    mov qword [abs process_one + PROC_NEXT], process_two
    mov qword [abs process_two + PROC_NEXT], process_one
    mov qword [abs current_process], process_one
    mov dword [abs process_one + PROC_STATE], PROC_RUNNING
%if PROCESS_CREATE_TEST
    mov dword [abs process_create_test_armed], 1
%endif
    mov rax, [abs process_one + PROC_CR3]
    mov cr3, rax
    mov rax, [abs process_one + PROC_KTOP]
    mov [abs tss64 + 4], eax
    mov dword [abs tss64 + 8], 0
    mov rcx, USER_CODE
    mov r11, 0x202
    mov rsp, USER_STACK_TOP
    db 0x48, 0x0f, 0x07       ; SYSRETQ
.load_fail:
    cli
.halt: hlt
    jmp .halt
