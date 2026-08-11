syscall_entry:
    ; SYSCALL does not perform a hardware stack switch.  Save the complete
    ; user return state in the current process object, then enter its guarded
    ; kernel stack.  No selector is allowed to touch a caller buffer except
    ; through user_span_valid/copy_user helpers below.
    mov rbx, [abs current_process]
    test rbx, rbx
    jz .kernel_bad
    mov [rbx + PROC_RIP], rcx
    mov [rbx + PROC_FLAGS], r11d
    mov [rbx + PROC_RSP], rsp
    mov rsp, [rbx + PROC_KTOP]
    cmp eax, strict byte SYS_CONSOLE_READ  ; console_read (non-blocking Alpha seed)
    je .read
    cmp eax, strict byte SYS_CONSOLE_WRITE  ; console_write
    je .write
    cmp eax, strict byte SYS_MEM_GROW       ; mem_grow
    je .mem_grow
    cmp eax, strict byte SYS_FILE_OPEN      ; file_open
    je .file_open
    cmp eax, strict byte SYS_FILE_READ      ; file_read
    je .file_read
    cmp eax, strict byte SYS_FILE_WRITE     ; file_write
    je .file_write
    cmp eax, strict byte SYS_FILE_CLOSE     ; file_close
    je .file_close
    cmp eax, strict byte SYS_FILE_STAT      ; file_stat
    je .file_stat
    cmp eax, strict byte SYS_PATH_CREATE    ; path_create
    je .path_create
    cmp eax, strict byte SYS_FILE_UNLINK    ; file_unlink
    je .file_unlink
    cmp eax, strict byte SYS_PROCESS_SPAWN ; process_spawn(image, size)
    je .process_spawn
    cmp eax, strict byte SYS_PROCESS_WAIT  ; process_wait(pid)
    je .process_wait
    cmp eax, strict byte SYS_PROCESS_SPAWN_ARGS ; process_spawn_args(image, size, args, args_len)
    je .process_spawn_args
    cmp eax, strict byte SYS_PROCESS_ARGS  ; process_args(buffer, capacity)
    je .process_args
    cmp eax, strict byte SYS_FILE_LIST     ; file_list(buffer, capacity)
    je .file_list
    cmp eax, strict byte SYS_PROCESS_EXIT  ; process_exit
    je .exit
    cmp eax, strict byte SYS_TASK_YIELD    ; task_yield
    je .yield
    mov rax, -38                ; -ENOSYS
    jmp .return_user
.kernel_bad:
    cli
.halt: hlt
    jmp .halt
.read:
    call console_read_user
    jmp .return_user
.write:
    mov al, 'S'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, '1'
    out 0xe9, al
    mov byte [abs user_syscall_seen], 1
    call console_write_user
    jmp .return_user
.mem_grow:
    ; Grow by at most one page in the Alpha ABI.  The new page is allocated and
    ; inserted in the current process's PT before the break is committed; an
    ; exhaustion error therefore leaves the old break unchanged.
    mov rbx, [abs current_process]
    mov rax, [rbx + PROC_HEAP]
    test rdi, rdi
    jz .mem_return
    cmp rdi, PAGE_SIZE
    ja .mem_fail
    add rax, PAGE_SIZE
    jc .mem_fail
    cmp rax, USER_LIMIT
    jae .mem_fail
    mov r9, rax
    mov r8, rax
    sub r8, PAGE_SIZE
    mov r12, r8
    mov rdi, rbx
    mov rsi, r8
    call process_map_page
    test eax, eax
    jz .mem_fail
    ; process_map_page legitimately clobbers volatile r9 while allocating.
    ; Reconstruct the committed break from the preserved mapped-page address.
    lea r9, [r12 + PAGE_SIZE]
    mov [rbx + PROC_HEAP], r9
    mov rax, r12
    jmp .return_user
.mem_return:
    mov rax, [rbx + PROC_HEAP]
    jmp .return_user
.mem_fail:
    mov rax, -12                ; -ENOMEM
    jmp .return_user
.file_open:
    call gfs_file_open_user
    jmp .return_user
.file_read:
    call gfs_file_read_user
    jmp .return_user
.file_write:
    call gfs_file_write_user
    jmp .return_user
.file_close:
    call gfs_file_close_user
    jmp .return_user
.file_stat:
    call gfs_file_stat_user
    jmp .return_user
.path_create:
    call gfs_path_create_user
    jmp .return_user
.file_unlink:
    call gfs_file_unlink_user
    jmp .return_user
.process_spawn:
    call process_spawn_user
    jmp .return_user
.process_wait:
    call process_wait_user
    jmp .return_user
.process_spawn_args:
    ; SYSCALL itself overwrites RCX with the user return RIP.  The ring-3
    ; import therefore carries argv_len in R8 and the kernel restores the
    ; fourth ABI argument before entering the checked spawn path.
    mov rcx, r8
    call process_spawn_user_args
    jmp .return_user
.process_args:
    call process_args_user
    jmp .return_user
.file_list:
    call gfs_file_list_user
    jmp .return_user
.exit:
    mov al, 'S'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    mov byte [abs user_done], 1
    jmp process_exit_current
.yield:
    ; A cooperative yield is also a VM scheduling boundary.  Reset the
    ; per-dispatch instruction budget so an idle shell does not self-terminate
    ; merely because console_read returned -EAGAIN repeatedly.
    mov rbx, [abs current_process]
    mov r8, [rbx + PROC_STACK]
    mov qword [r8 + 16], 0
    jmp process_yield_current
.return_user:
    mov rbx, [abs current_process]
    mov rcx, [rbx + PROC_RIP]
    mov r11, [rbx + PROC_FLAGS]
    mov rsp, [rbx + PROC_RSP]
    db 0x48, 0x0f, 0x07       ; SYSRETQ

console_read_user:
    ; RDI=user buffer, RSI=count.  The keyboard IRQ feeds a bounded byte ring;
    ; reads are non-blocking and return -EAGAIN when it is empty.
    cmp rsi, 256
    ja .invalid
    test rsi, rsi
    jz .empty
    call user_span_valid
    test eax, eax
    jz .fault
    mov r8, rdi
    xor r9d, r9d
.next:
    cmp r9, rsi
    jae .done
    movzx eax, byte [abs console_input_head]
    cmp al, [abs console_input_tail]
    je .again
    movzx edx, al
    mov al, [abs console_input_buffer + rdx]
    mov [r8 + r9], al
    inc dl
    and dl, 0xff
    mov [abs console_input_head], dl
    inc r9
    jmp .next
.again:
    test r9, r9
    jnz .done
    mov eax, -11
    ret
.done:
    mov rax, r9
    ret
.empty:
    xor eax, eax
    ret
.invalid:
    mov eax, -22
    ret
.fault:
    mov eax, -14
    ret

console_write_user:
    ; RDI=user bytes, RSI=count.  Return bytes written or a negative errno.
    test rsi, rsi
    jz .empty
    call user_span_valid
    test eax, eax
    jz .bad
    mov r8, rsi
    xor eax, eax
.loop:
    test r8, r8
    jz .done
    mov al, [rdi]
    call console_write_char
    inc rdi
    dec r8
    jmp .loop
.done:
    mov rax, rsi
    ret
.empty:
    xor eax, eax
    ret
.bad:
    mov rax, -14                ; -EFAULT
    ret

user_span_valid:
    ; Validate every page in [RDI,RDI+RSI).  The current process PT is the
    ; sole authority; a range check alone would accept the unmapped guard.
    test rsi, rsi
    jz .ok
    cmp rdi, USER_BASE
    jb .bad
    mov rax, rdi
    add rax, rsi
    jc .bad
    cmp rax, USER_LIMIT
    ja .bad
    mov r8, [abs current_process]
    mov r8, [r8 + PROC_PT]
    mov r9, rdi
    sub r9, USER_BASE
    shr r9, 12
    mov r10, rax
    dec r10
    sub r10, USER_BASE
    shr r10, 12
.page:
    cmp r9, 512
    jae .bad
    test qword [r8 + r9 * 8], 1
    jz .bad
    cmp r9, r10
    jae .ok
    inc r9
    jmp .page
.ok:
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

process_spawn_user:
    ; RDI=user GWO2 image, RSI=image bytes.  The image is copied through the
    ; same user-span proof as every other syscall, verified in a kernel-owned
    ; buffer, then installed into the reusable child slot only after the old
    ; child has been fully reaped.
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    cmp r13, 48
    jb .invalid
    cmp r13, MAX_GWO_IMAGE_BYTES
    ja .invalid
    mov rdi, r12
    mov rsi, r13
    call user_span_valid
    test eax, eax
    jz .fault
    mov rsi, r12
    mov rdi, user_gwo_staging
    mov rcx, r13
    rep movsb
    mov rdi, user_gwo_staging
    mov esi, r13d
    call gwo_load_image
    test eax, eax
    jz .bad_exec
    mov r14, process_two
    cmp r14, [abs current_process]
    je .busy
    cmp dword [r14 + PROC_STATE], PROC_EXITED
    jne .busy
    mov rdx, user_payload_kernel
    mov ecx, [abs user_payload_size]
    mov rdi, r14
    mov esi, 2
    call process_create
    test rax, rax
    jz .no_memory
    mov qword [abs process_one + PROC_NEXT], process_two
    mov qword [abs process_two + PROC_NEXT], process_one
    mov eax, 2
    jmp .done
.invalid:
    mov eax, -22
    jmp .done
.fault:
    mov eax, -14
    jmp .done
.bad_exec:
    mov eax, -8
    jmp .done
.busy:
    mov eax, -16
    jmp .done
.no_memory:
    mov eax, -12
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

process_spawn_user_args:
    ; RDI/RSi contain the image and size, RDX/RCX contain a bounded NUL-
    ; separated argument block.  Arguments are copied before the child is
    ; published so a failed spawn cannot expose a partially initialized ABI.
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    cmp r15, MAX_PROCESS_ARGS
    ja .invalid
    mov rdi, r14
    mov rsi, r15
    call user_span_valid
    test eax, eax
    jz .fault
    test r15, r15
    jz .copy_args
    mov rax, r14
    add rax, r15
    jc .invalid
    dec rax
    cmp byte [rax], 0
    jne .invalid
.copy_args:
    mov rsi, r14
    mov rdi, process_two_args
    mov rcx, r15
    rep movsb
    mov rdi, r12
    mov rsi, r13
    call process_spawn_user
    cmp eax, 2
    jne .done
    mov qword [abs process_two + PROC_ARG_PTR], process_two_args
    mov [abs process_two + PROC_ARG_LEN], r15
    jmp .done
.invalid:
    mov eax, -22
    jmp .done
.fault:
    mov eax, -14
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

process_args_user:
    ; RDI=destination, RSI=capacity.  Return the complete serialized argv
    ; length; callers must provide enough space instead of receiving a silent
    ; truncation that could change a source or output path.
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rbx, [abs current_process]
    mov rdx, [rbx + PROC_ARG_LEN]
    cmp rdx, r13
    ja .space
    mov rdi, r12
    mov rsi, rdx
    call user_span_valid
    test eax, eax
    jz .fault
    mov rsi, [rbx + PROC_ARG_PTR]
    mov rdi, r12
    mov rcx, rdx
    rep movsb
    mov rax, rdx
    jmp .done
.space:
    mov eax, -28
    jmp .done
.fault:
    mov eax, -14
.done:
    pop r13
    pop r12
    ret

process_wait_user:
    ; Alpha keeps a single reusable child slot.  Waiting is deliberately
    ; non-blocking: -EAGAIN lets the Grown caller yield and retry without
    ; hiding scheduler progress inside a syscall.
    cmp rdi, 2
    jne .invalid
    cmp dword [abs process_two + PROC_PID], 2
    jne .invalid
    cmp dword [abs process_two + PROC_STATE], PROC_EXITED
    jne .again
    movsxd rax, dword [abs process_two + PROC_EXIT_STATUS]
    ret
.again:
    mov eax, -11
    ret
.invalid:
    mov eax, -22
    ret

process_load_context:
    ; RDI=next process.  The caller immediately returns through SYSRET, so
    ; this routine only changes ownership state and the address-space root.
    mov [abs current_process], rdi
    mov dword [rdi + PROC_STATE], PROC_RUNNING
    mov rax, [rdi + PROC_CR3]
    mov cr3, rax
    mov rax, [rdi + PROC_KTOP]
    mov [abs tss64 + 4], eax
    mov dword [abs tss64 + 8], 0
    ret

process_next_ready:
    ; RDI=current process.  Alpha's fixed process table still uses the same
    ; run-queue rule as the dynamic implementation: scan each owned node once
    ; and accept only READY/RUNNING states.
    mov r8, rdi
    mov rax, [rdi + PROC_NEXT]
.scan:
    test rax, rax
    jz .none
    cmp dword [rax + PROC_STATE], PROC_READY
    je .found
    cmp rax, r8
    je .none
    mov rax, [rax + PROC_NEXT]
    jmp .scan
.found:
    ret
.none:
    xor eax, eax
    ret

process_yield_current:
    mov rbx, [abs current_process]
    ; A cooperative yield enters through SYSCALL rather than an IRQ, so there
    ; is no hardware iret frame to retain.  Materialize the saved syscall
    ; return tuple in the process-owned context slot before another process
    ; can be selected by a timer interrupt.
    mov r8, [rbx + PROC_CONTEXT]
    mov rdi, r8
    xor eax, eax
    mov ecx, 20
    rep stosq
    ; The native GrVM keeps its live program counter, operand-stack depth,
    ; instruction budget, and call-frame depth in callee-saved registers.  A
    ; cooperative yield has no hardware register frame, so materialize those
    ; values explicitly; otherwise resuming after an empty console read would
    ; restart with r12/r13/r14/r15 cleared and corrupt the user program.
    mov rax, [abs VM_FP_SLOT]
    mov [r8], rax
    mov rax, [abs VM_STEP_SLOT]
    mov [r8 + 8], rax
    mov rax, [abs VM_SP_SLOT]
    mov [r8 + 16], rax
    mov rax, [abs VM_PC_SLOT]
    mov [r8 + 24], rax
    mov rax, [rbx + PROC_RIP]
    mov [r8 + 120], rax
    mov qword [r8 + 128], 0x33
    mov rax, [rbx + PROC_FLAGS]
    mov [r8 + 136], rax
    mov rax, [rbx + PROC_RSP]
    mov [r8 + 144], rax
    mov qword [r8 + 152], 0x2b
    mov rdi, rbx
    call process_next_ready
    test rax, rax
    jz .return
    mov r12, rax
    mov dword [rbx + PROC_STATE], PROC_READY
    mov rdi, r12
    call process_load_context
.return:
    mov rbx, [abs current_process]
    mov rax, [rbx + PROC_CONTEXT]
    jmp process_iret_context

process_exit_current:
    mov rbx, [abs current_process]
    mov dword [rbx + PROC_STATE], PROC_EXITED
    mov dword [rbx + PROC_EXIT_STATUS], edi
    mov rdi, rbx
    call process_next_ready
    test rax, rax
    jz .kernel_shell
    mov r12, rax
    mov r13, rbx
    mov rdi, r12
    call process_load_context
    mov rsp, [r12 + PROC_KTOP]
    mov rdi, r13
    call process_reap
%if RESOURCE_TEST
    mov rdi, r13
    call resource_test_emit_snapshot
%endif
    mov rax, [r12 + PROC_CONTEXT]
    jmp process_iret_context
.kernel_shell:
    mov rsp, 0x90000
    mov rdi, rbx
    call process_reap
%if RESOURCE_TEST
    mov rdi, rbx
    call resource_test_emit_snapshot
%endif
    mov qword [abs current_process], 0
    mov eax, KERNEL_CR3
    mov cr3, rax
    mov dword [abs tss64 + 4], 0x90000
    mov dword [abs tss64 + 8], 0
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    jmp after_user_mode
