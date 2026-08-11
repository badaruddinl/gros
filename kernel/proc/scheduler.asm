scheduler_seed:
    ; Two task descriptors: next, entry, state, saved interrupt context, and
    ; bootstrap stack metadata. The descriptors are first exercised through
    ; scheduler_run, then promoted to independently stacked timer contexts.
    mov rdi, 40
    call heap_alloc
    test rax, rax
    jz .fail
    mov rbx, rax
    mov qword [rbx], 0
    mov rax, task_one
    mov [rbx + 8], rax
    mov dword [rbx + 16], 0
    mov [abs run_queue], rbx
    mov [abs scheduler_task_one], rbx
    mov rdi, 40
    call heap_alloc
    test rax, rax
    jz .fail
    mov qword [rax], 0
    mov rcx, task_two
    mov [rax + 8], rcx
    mov dword [rax + 16], 0
    mov [rbx], rax
    mov [abs scheduler_task_two], rax
    call scheduler_run
    mov rbx, [abs scheduler_task_one]
    mov rax, [abs scheduler_task_two]
    mov dword [rbx + 16], 0
    mov dword [rax + 16], 0
    mov rcx, task_one_context
    mov [rbx + 8], rcx
    mov rcx, task_two_context
    mov [rax + 8], rcx
    mov rdi, rbx
    mov rsi, 0x92000
    mov rdx, task_one_context
    call scheduler_prepare_context
    mov rdi, [abs scheduler_task_two]
    mov rsi, 0x93000
    mov rdx, task_two_context
    call scheduler_prepare_context
    mov rbx, [abs scheduler_task_one]
    mov rax, [abs scheduler_task_two]
    mov qword [rbx], rax
    mov qword [rax], 0
    mov qword [abs scheduler_current], 0
    mov qword [abs scheduler_kernel_context], 0
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

scheduler_run:
    mov rsi, [abs run_queue]
.next:
    test rsi, rsi
    jz .done
    cmp dword [rsi + 16], 0
    jne .advance
    call qword [rsi + 8]
    mov dword [rsi + 16], 1
.advance:
    mov rsi, [rsi]
    jmp .next
.done:
    ret

scheduler_prepare_context:
    ; RDI=descriptor, RSI=stack top, RDX=entry. Build the same register and
    ; CPU-return frame produced by irq_timer_stub without disturbing its caller.
    mov r8, rsp
    mov rsp, rsi
    push qword 0x202
    push qword 0x18
    push rdx
    xor eax, eax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    push rax
    mov [rdi + 24], rsp
    mov rsp, r8
    ret

scheduler_tick:
    ; RDI points at the complete saved frame for the interrupted context.
    ; The return value is the frame pointer selected for the next iretq.
    mov rax, [abs scheduler_current]
    test rax, rax
    jz .from_kernel
    mov [rax + 24], rdi
    mov rbx, [rax]
    test rbx, rbx
    jnz .select_task
    mov qword [abs scheduler_current], 0
    mov rax, [abs scheduler_kernel_context]
    ret
.from_kernel:
    mov [abs scheduler_kernel_context], rdi
    mov rbx, [abs run_queue]
.select_task:
    mov [abs scheduler_current], rbx
    mov rax, [rbx + 24]
    ret

task_one:
    mov al, 'T'
    out 0xe9, al
    mov al, '1'
    out 0xe9, al
    ret

task_two:
    mov al, 'T'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    ret

task_one_context:
    mov rsp, 0x92000
    mov al, 'P'
    out 0xe9, al
    mov al, '1'
    out 0xe9, al
.wait:
    hlt
    jmp .wait
task_two_context:
    mov rsp, 0x93000
    mov al, 'P'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
.wait:
    hlt
    jmp .wait
