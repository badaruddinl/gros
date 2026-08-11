user_vm_program_marker:
    db 'V', 'M', 'P', '2'
user_vm_program:
    xor r13d, r13d
    xor r14d, r14d
    mov r12, USER_CODE + VM_BLOB_OFFSET
    add r12, [abs VM_ENTRY_SLOT]
    xor eax, eax
    mov rdi, VM_STACK_BASE
    mov ecx, VM_STACK_SLOTS
    rep stosq
    mov qword [abs VM_CONST_CURSOR], VM_CONST_BASE
    mov rdi, VM_CONST_CACHE_BASE
    xor eax, eax
    mov ecx, VM_CONST_CACHE_BYTES / 8
    rep stosq
    mov qword [abs VM_FP_SLOT], 0
.loop:
    inc r14
    cmp r14, VM_INSTRUCTION_LIMIT
    jae .fail
    cmp r12, [abs VM_LIMIT_SLOT]
    jae .fail
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    movzx eax, byte [r12]
    inc r12
    cmp eax, 1
    je .const
    cmp eax, 2
    je .load_local
    cmp eax, 3
    je .store_local
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
    cmp eax, 4
    jb .check_jump
    cmp eax, 9
    jbe .arithmetic
.check_jump:
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
    jmp .fail
.const:
    cmp r13, VM_STACK_SLOTS
    jae .fail
    movsxd rax, dword [r12]
    add r12, 4
    mov [VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.load_local:
    movzx eax, byte [r12]
    inc r12
    cmp eax, 255
    jae .fail
    cmp r13, VM_STACK_SLOTS
    jae .fail
    mov r8, [abs VM_FP_SLOT]
    imul r8, VM_FRAME_STRIDE
    add r8, VM_FRAME_BASE + VM_FRAME_LOCALS
    mov rax, [r8 + rax * 8]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.store_local:
    cmp r13, 1
    jb .fail
    movzx eax, byte [r12]
    inc r12
    cmp eax, 255
    jae .fail
    dec r13
    mov rdx, [abs VM_STACK_BASE + r13 * 8]
    mov r8, [abs VM_FP_SLOT]
    imul r8, VM_FRAME_STRIDE
    add r8, VM_FRAME_BASE + VM_FRAME_LOCALS
    mov [r8 + rax * 8], rdx
    jmp .loop
.byte_const:
    movzx eax, byte [r12]
    inc r12
    mov r10, r12
    add r10, rax
    jc .fail
    cmp r10, [abs VM_LIMIT_SLOT]
    ja .fail
    ; Literal instructions execute inside compiler loops.  Cache the copied
    ; pointer by instruction address so repeated iterations do not consume
    ; the bounded constant arena.
    mov r11, [abs VM_PC_SLOT]
    mov rdx, VM_CONST_CACHE_BASE
    xor ebx, ebx
.cache_scan:
    cmp ebx, VM_CONST_CACHE_SLOTS
    jae .fail
    lea rdi, [rdx + rbx * 8]
    lea rdi, [rdi + rbx * 8]
    mov r8, [rdi]
    test r8, r8
    jz .cache_miss
    cmp r8, r11
    je .cache_hit
    inc ebx
    jmp .cache_scan
.cache_hit:
    cmp r13, VM_STACK_SLOTS
    jae .fail
    mov r8, [rdi + 8]
    mov [abs VM_STACK_BASE + r13 * 8], r8
    inc r13
    mov r12, r10
    jmp .loop
.cache_miss:
    mov r8, [abs VM_CONST_CURSOR]
    mov r9, r8
    add r9, rax
    inc r9
    cmp r9, VM_CONST_LIMIT
    ja .fail
    cmp r13, VM_STACK_SLOTS
    jae .fail
    mov rdi, r8
    mov rsi, r12
    mov rcx, rax
    rep movsb
    mov byte [r8 + rax], 0
    mov [abs VM_CONST_CURSOR], r9
    lea rdi, [rdx + rbx * 8]
    lea rdi, [rdi + rbx * 8]
    mov [rdi], r11
    mov [rdi + 8], r8
    mov [abs VM_STACK_BASE + r13 * 8], r8
    inc r13
    mov r12, r10
    jmp .loop
.byte_load:
    cmp r13, 2
    jb .fail
    mov rax, [abs VM_STACK_BASE + r13 * 8 - 8]
    mov rbx, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov r10, rax
    test rax, rax
    js .fail
    add rbx, rax
    jc .fail
    mov rdi, rbx
    mov esi, 1
    call user_vm_span_valid
    test eax, eax
    jz .fail
    movzx eax, byte [rbx]
    mov [abs VM_STACK_BASE + r13 * 8 - 16], rax
    dec r13
    jmp .loop
.byte_store:
    cmp r13, 3
    jb .fail
    mov rax, [abs VM_STACK_BASE + r13 * 8 - 8]
    mov rbx, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rdx, [abs VM_STACK_BASE + r13 * 8 - 24]
    mov r8b, al
    test rbx, rbx
    js .fail
    add rdx, rbx
    jc .fail
    mov rdi, rdx
    mov esi, 1
    call user_vm_span_valid
    test eax, eax
    jz .fail
    mov [rdx], r8b
    sub r13, 3
    jmp .loop
.duplicate:
    cmp r13, VM_STACK_SLOTS
    jae .fail
    test r13, r13
    jz .fail
    mov rax, [abs VM_STACK_BASE + r13 * 8 - 8]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.drop:
    test r13, r13
    jz .fail
    dec r13
    jmp .loop
.arithmetic:
    cmp r13, 2
    jb .fail
    dec r13
    mov rax, [abs VM_STACK_BASE + r13 * 8]
    dec r13
    mov rbx, [abs VM_STACK_BASE + r13 * 8]
    cmp byte [r12 - 1], 4
    je .add
    cmp byte [r12 - 1], 5
    je .sub
    cmp byte [r12 - 1], 6
    je .mul
    cmp byte [r12 - 1], 7
    je .div
    cmp byte [r12 - 1], 8
    je .eq
    cmp byte [r12 - 1], 9
    je .lt
    cmp byte [r12 - 1], 22
    je .xor
    jmp .fail
.add:
    add ebx, eax
    movsxd rax, ebx
    jmp .binary_push
.sub:
    sub ebx, eax
    movsxd rax, ebx
    jmp .binary_push
.mul:
    imul ebx, eax
    movsxd rax, ebx
    jmp .binary_push
.div:
    test rax, rax
    jz .fail
    mov rcx, rax
    mov rax, rbx
    cqo
    idiv rcx
    jmp .binary_push
.eq:
    cmp rbx, rax
    sete al
    movzx eax, al
    jmp .binary_push
.lt:
    cmp rbx, rax
    setl al
    movzx eax, al
    jmp .binary_push
.xor:
    xor ebx, eax
    movsxd rax, ebx
.binary_push:
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.jump:
    movsx rax, word [r12]
    add r12, 2
    add r12, rax
    cmp r12, USER_CODE + VM_BLOB_OFFSET
    jb .fail
    cmp r12, [abs VM_LIMIT_SLOT]
    jae .fail
    jmp .loop
.jump_zero:
    cmp r13, 1
    jb .fail
    dec r13
    mov rax, [abs VM_STACK_BASE + r13 * 8]
    movsx rbx, word [r12]
    add r12, 2
    test rax, rax
    jnz .loop
    add r12, rbx
    cmp r12, USER_CODE + VM_BLOB_OFFSET
    jb .fail
    cmp r12, [abs VM_LIMIT_SLOT]
    jae .fail
    jmp .loop
.import:
    movzx eax, byte [r12]
    inc r12
    movzx ebx, byte [r12]
    inc r12
    cmp eax, strict byte GWO_IMPORT_PRINT_I32
    je .import_print
    cmp eax, strict byte GWO_IMPORT_EXIT
    je .import_exit
    cmp eax, strict byte GWO_IMPORT_NEWLINE
    je .import_newline
    cmp eax, strict byte GWO_IMPORT_CONSOLE_READ
    je .import_console_read
    cmp eax, strict byte GWO_IMPORT_FILE_OPEN
    je .import_file_open
    cmp eax, strict byte GWO_IMPORT_FILE_READ
    je .import_file_read
    cmp eax, strict byte GWO_IMPORT_FILE_WRITE
    je .import_file_write
    cmp eax, strict byte GWO_IMPORT_FILE_CLOSE
    je .import_file_close
    cmp eax, strict byte GWO_IMPORT_FILE_STAT
    je .import_file_stat
    cmp eax, strict byte GWO_IMPORT_MEM_GROW
    je .import_mem_grow
    cmp eax, strict byte GWO_IMPORT_PATH_CREATE
    je .import_path_create
    cmp eax, strict byte GWO_IMPORT_FILE_UNLINK
    je .import_file_unlink
    cmp eax, strict byte GWO_IMPORT_PRINT_BYTES
    je .import_print_bytes
    cmp eax, strict byte GWO_IMPORT_TASK_YIELD
    je .import_task_yield
    cmp eax, strict byte GWO_IMPORT_PROCESS_SPAWN
    je .import_process_spawn
    cmp eax, strict byte GWO_IMPORT_PROCESS_WAIT
    je .import_process_wait
    cmp eax, strict byte GWO_IMPORT_PROCESS_SPAWN_ARGS
    je .import_process_spawn_args
    cmp eax, strict byte GWO_IMPORT_PROCESS_ARGS
    je .import_process_args
    cmp eax, strict byte GWO_IMPORT_FILE_LIST
    je .import_file_list
    jmp .fail
.import_console_read:
    cmp ebx, 2
    jne .fail
    cmp r13, 2
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 2
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_CONSOLE_READ
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_file_open:
    cmp ebx, 2
    jne .fail
    cmp r13, 2
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 2
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_FILE_OPEN
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_file_read:
    cmp ebx, 3
    jne .fail
    cmp r13, 3
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 24]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rdx, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 3
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_FILE_READ
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_file_write:
    cmp ebx, 3
    jne .fail
    cmp r13, 3
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 24]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rdx, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 3
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_FILE_WRITE
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_file_close:
    cmp ebx, 1
    jne .fail
    cmp r13, 1
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 8]
    dec r13
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_FILE_CLOSE
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_file_stat:
    cmp ebx, 2
    jne .fail
    cmp r13, 2
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 2
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_FILE_STAT
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_mem_grow:
    cmp ebx, 1
    jne .fail
    cmp r13, 1
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 8]
    dec r13
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_MEM_GROW
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_path_create:
    cmp ebx, 1
    jne .fail
    cmp r13, 1
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 8]
    dec r13
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_PATH_CREATE
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_file_unlink:
    cmp ebx, 1
    jne .fail
    cmp r13, 1
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 8]
    dec r13
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_FILE_UNLINK
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_print_bytes:
    cmp ebx, 2
    jne .fail
    cmp r13, 2
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 2
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_CONSOLE_WRITE
    syscall
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    jmp .loop
.import_task_yield:
    test ebx, ebx
    jnz .fail
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_TASK_YIELD
    syscall
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    jmp .loop
.import_process_spawn:
    cmp ebx, 2
    jne .fail
    cmp r13, 2
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 2
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_PROCESS_SPAWN
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_process_spawn_args:
    cmp ebx, 4
    jne .fail
    cmp r13, 4
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 32]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 24]
    mov rdx, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rcx, [abs VM_STACK_BASE + r13 * 8 - 8]
    mov r8, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 4
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_PROCESS_SPAWN_ARGS
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_process_args:
    cmp ebx, 2
    jne .fail
    cmp r13, 2
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 2
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_PROCESS_ARGS
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_file_list:
    cmp ebx, 2
    jne .fail
    cmp r13, 2
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 16]
    mov rsi, [abs VM_STACK_BASE + r13 * 8 - 8]
    sub r13, 2
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_FILE_LIST
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.import_process_wait:
    cmp ebx, 1
    jne .fail
    cmp r13, 1
    jb .fail
    mov rdi, [abs VM_STACK_BASE + r13 * 8 - 8]
    dec r13
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, SYS_PROCESS_WAIT
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.call:
    movzx eax, word [r12]
    mov r9, rax
    add r12, 2
    movzx ebx, byte [r12]
    inc r12
    movzx ecx, byte [r12]
    inc r12
    cmp ebx, 255
    ja .fail
    cmp ecx, 1
    ja .fail
    cmp r13, rbx
    jb .fail
    mov r15, [abs VM_FP_SLOT]
    inc r15
    cmp r15, VM_FRAME_COUNT
    jae .fail
    mov rdx, r13
    sub rdx, rbx
    mov r8, r15
    imul r8, VM_FRAME_STRIDE
    add r8, VM_FRAME_BASE
    mov [r8], r12
    mov [r8 + 8], rdx
    mov [r8 + 16], rcx
    lea rdi, [r8 + VM_FRAME_LOCALS]
    xor eax, eax
    mov ecx, 255
    rep stosq
    mov [abs VM_FP_SLOT], r15
    mov r12, USER_CODE + VM_BLOB_OFFSET
    add r12, r9
    cmp r12, [abs VM_LIMIT_SLOT]
    jae .fail
    jmp .loop
.import_print:
    cmp ebx, 1
    jne .fail
    cmp r13, 1
    jb .fail
    dec r13
    mov rax, [abs VM_STACK_BASE + r13 * 8]
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    call vm_print_i32
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    jmp .loop
.import_newline:
    test ebx, ebx
    jnz .fail
    mov byte [abs VM_BUFFER], 10
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, 2
    mov edi, VM_BUFFER
    mov esi, 1
    syscall
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov r15, [abs VM_FP_SLOT]
    jmp .loop
.import_exit:
    cmp ebx, 1
    jne .fail
    cmp r13, 1
    jb .fail
    dec r13
    mov edi, [abs VM_STACK_BASE + r13 * 8]
    mov eax, 0x0b
    syscall
    jmp .fail
.return:
    cmp r13, 1
    jb .fail
    dec r13
    mov rax, [abs VM_STACK_BASE + r13 * 8]
    mov r15, [abs VM_FP_SLOT]
    test r15, r15
    jz .return_main
    mov r8, r15
    imul r8, VM_FRAME_STRIDE
    add r8, VM_FRAME_BASE
    mov rdx, [r8 + 8]
    mov r12, [r8]
    mov rcx, [r8 + 16]
    dec r15
    mov [abs VM_FP_SLOT], r15
    mov r13, rdx
    test rcx, rcx
    jz .loop
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.return_main:
    mov edi, eax
    mov eax, 0x0b
    syscall
    jmp .fail
.return_void:
    mov r15, [abs VM_FP_SLOT]
    test r15, r15
    jz .halt
    mov r8, r15
    imul r8, VM_FRAME_STRIDE
    add r8, VM_FRAME_BASE
    mov r13, [r8 + 8]
    mov r12, [r8]
    dec r15
    mov [abs VM_FP_SLOT], r15
    jmp .loop
.halt:
    xor edi, edi
    mov eax, 0x0b
    syscall
.fail:
    mov edi, 1
    mov eax, 0x0b
    syscall
.halt_forever:
    cli
    hlt
    jmp .halt_forever

user_vm_span_valid:
    ; Ring-3 VM memory helpers cannot call the kernel's page-table validator.
    ; Keep their range proof local and rely on the mapped-page fault boundary
    ; for the guard hole; a fault terminates only this process.
    test rsi, rsi
    jz .vm_span_ok
    cmp rdi, USER_BASE
    jb .vm_span_bad
    mov rax, rdi
    add rax, rsi
    jc .vm_span_bad
    cmp rax, USER_LIMIT
    ja .vm_span_bad
.vm_span_ok:
    mov eax, 1
    ret
.vm_span_bad:
    xor eax, eax
    ret

vm_print_i32:
    ; RAX=i32 sign-extended.  Render backwards into the user buffer, then
    ; use the checked console_write syscall; no kernel-side formatting exists.
    mov rbx, rax
    xor r8d, r8d
    test rbx, rbx
    jns .positive
    neg rbx
    mov r8d, 1
.positive:
    lea rdi, [abs VM_BUFFER + 32]
    xor ecx, ecx
    test rbx, rbx
    jnz .digits
    dec rdi
    mov byte [rdi], '0'
    mov ecx, 1
    jmp .sign
.digits:
    xor edx, edx
    mov rax, rbx
    mov r9, 10
    div r9
    mov rbx, rax
    add dl, '0'
    dec rdi
    mov [rdi], dl
    inc ecx
    test rbx, rbx
    jnz .digits
.sign:
    test r8d, r8d
    jz .write
    dec rdi
    mov byte [rdi], '-'
    inc ecx
.write:
    mov esi, ecx
    mov eax, 2
    syscall
    ret
user_vm_program_end:

isr_invalid_opcode:
    ; CPU frame for a no-error-code exception is [RIP, CS, RFLAGS] at entry.
    ; The seed preserves the scratch register before its fail-stop report.
    push rax
    mov al, 'E'
    out 0xe9, al
    mov al, 'X'
    out 0xe9, al
    mov al, '0'
    out 0xe9, al
    mov al, '6'
    out 0xe9, al
    pop rax
    cli
.halt: hlt
    jmp .halt

isr_page_fault:
    ; Error-code exception frame: [error, RIP, CS, RFLAGS, RSP, SS] for ring
    ; 3.  A kernel fault remains fail-stop; a user fault is handed to the
    ; process teardown path and never executes the kernel halt path.
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
    test qword [rsp + 136], 3
    jz .kernel
    mov al, 'P'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    mov rdi, rsp
    call process_fault_current
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
.kernel:
    mov al, 'K'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    cli
.halt: hlt
    jmp .halt

isr_default:
    ; Deliberately fail-stop: unknown vectors use the same explicit frame policy.
    jmp isr_invalid_opcode

align 8
