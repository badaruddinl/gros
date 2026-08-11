process_iret_context:
    ; RAX points at a process-owned full register/iret frame.  Cooperative
    ; yields and exits must restore this frame, not restart the native VM at
    ; PROC_RIP: a timer may already have saved the VM's live PC and registers
    ; there.  The frame layout matches irq_timer_stub exactly.
    mov rsp, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

process_timer_tick:
    ; RDI=register-save pointer created by irq_timer_stub.  Preserve the
    ; interrupted frame in the current process, then return the next process
    ; frame to the same stub.  The stub's pop/iret sequence is therefore
    ; identical for a fresh process and a preempted one.
    mov rbx, [abs current_process]
    test rbx, rbx
    jz .same
    mov r8, [rbx + PROC_CONTEXT]
    mov rsi, rdi
    mov rdi, r8
    mov ecx, 20
    rep movsq
    mov rdi, rbx
    mov dword [rbx + PROC_STATE], PROC_READY
    mov rdi, rbx
    call process_next_ready
    test rax, rax
    jz .same_current
    mov r12, rax
    mov rdi, r12
    call process_load_context
    mov rax, [r12 + PROC_CONTEXT]
    ret
.same_current:
    mov dword [rbx + PROC_STATE], PROC_RUNNING
.same:
    mov rax, rdi
    ret

process_fault_current:
    ; User faults are ordinary process exits.  The kernel mappings and the
    ; filesystem remain live while the next user context is resumed.
    mov rbx, [abs current_process]
    mov dword [rbx + PROC_STATE], PROC_EXITED
    mov dword [rbx + PROC_EXIT_STATUS], -14
    mov rdi, rbx
    call process_next_ready
    test rax, rax
    jz process_exit_current.kernel_shell
    mov r12, rax
    mov r13, rbx
    mov rdi, r12
    call process_load_context
    mov rax, [r12 + PROC_CONTEXT]
    ret

irq_timer_stub:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    cmp byte [abs timer_seen], 0
    jne .ack
    mov byte [abs timer_seen], 1
    mov al, 'I'
    out 0xe9, al
    mov al, 'R'
    out 0xe9, al
    mov al, 'Q'
    out 0xe9, al
.ack:
    mov rdi, rsp
    ; A ring-3 interrupt frame has CS at +128 (after the 15 saved GPRs).
    ; Kernel contexts retain the original bootstrap scheduler; user contexts
    ; use the owned process run queue and a full five-word iret frame.
    test qword [rsp + 128], 3
    jnz .user_tick
    call scheduler_tick
    mov rsp, rax
    jmp .restore
.user_tick:
    call process_timer_tick
    mov rsp, rax
.restore:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    mov al, 0x20
    out 0x20, al
    pop rax
    iretq

irq_keyboard_stub:
    push rax
    push rbx
    push rcx
    push rdx
    in al, 0x60
    mov [abs last_scancode], al
    test al, 0x80
    jnz .ack
    movzx ebx, al
    call keyboard_handle_scancode
.ack:
    mov al, 0x20
    out 0x20, al
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq
