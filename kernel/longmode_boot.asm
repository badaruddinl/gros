; Fase 10 experimental BIOS -> x86_64 long-mode trampoline.
bits 16
section .boot start=0 vstart=0x7c00
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    ; Stable bootstrap-info block: boot drive at 0000:5ffe.
    mov [0x5ffe], dl
    mov ah, 0x02
    mov al, 32
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [0x5ffe]
    mov bx, 0x8000
    int 0x13
    jc disk_fail
    jmp 0x0000:0x8000
disk_fail:
    cli
.halt: hlt
    jmp .halt
times 510-($-$$) db 0
dw 0xaa55

; loaded by sector two, at 0000:8000
section .stage2 start=512 vstart=0x8000
stage2:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    ; Fast A20 gate.
    in al, 0x92
    or al, 2
    out 0x92, al
    ; E820 map: retain entries at 0000:6000, count at 0000:5ffc.
    xor ax, ax
    mov es, ax
    mov di, 0x6000
    xor ebx, ebx
    mov word [0x5ffc], 0
.e820:
    mov eax, 0xe820
    mov edx, 0x534d4150
    mov ecx, 24
    int 0x15
    jc .e820_done
    cmp eax, 0x534d4150
    jne .fail
    add di, 24
    inc word [0x5ffc]
    test ebx, ebx
    jnz .e820
.e820_done:
    cmp word [0x5ffc], 0
    je .fail
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:protected_mode
.fail:
    cli
.halt: hlt
    jmp .halt

bits 32
protected_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000
    ; Zero PML4, PDPT, and PD at 0x1000..0x3fff.
    xor eax, eax
    mov edi, 0x1000
    mov ecx, 3072
    rep stosd
    mov dword [0x1000], 0x2003
    mov dword [0x2000], 0x3003
    mov dword [0x3000], 0x0083 ; 2 MiB identity map, present/write/huge
    mov eax, 0x1000
    mov cr3, eax
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    mov ecx, 0xc0000080
    rdmsr
    or eax, 1 << 8
    wrmsr
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp 0x18:long_mode

bits 64
long_mode:
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x90000
    lidt [abs idt_descriptor]
    mov al, 'L'
    out 0xe9, al
    mov al, 'M'
    out 0xe9, al
    mov al, '6'
    out 0xe9, al
    mov al, '4'
    out 0xe9, al
    mov al, 'I'
    out 0xe9, al
    mov al, 'D'
    out 0xe9, al
    mov al, 'T'
    out 0xe9, al
    call physical_memory_seed
    call heap_seed
    call scheduler_seed
    ud2                         ; vector 6 must enter isr_default below.
    cli
.halt: hlt
    jmp .halt

physical_memory_seed:
    ; First-MiB is permanently bootstrap/platform-reserved. Select the first
    ; page from an E820 type-1 usable range that is identity-mapped (< 2 MiB).
    xor ecx, ecx
    mov cx, [abs 0x5ffc]
    mov rsi, 0x6000
.next:
    test ecx, ecx
    jz .fail
    cmp dword [rsi + 16], 1
    jne .skip
    cmp dword [rsi + 4], 0
    jne .skip
    mov rax, [rsi]
    cmp rax, 0x100000
    jb .skip
    mov rdx, [rsi + 8]
    cmp rdx, 0x1000
    jb .skip
    mov r8, rax
    add r8, rdx
    add rax, 0xfff
    and rax, -0x1000
    cmp rax, 0x200000
    jae .skip
    mov rdx, rax
    add rdx, 0x1000
    cmp r8, rdx
    jb .skip
    mov [abs phys_first_free], rax
    mov dword [rax], 0x314d5246 ; "FRM1": prove selected frame is writable.
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
    ret
.skip:
    add rsi, 24
    dec ecx
    jmp .next
.fail:
    cli
.halt: hlt
    jmp .halt

heap_seed:
    ; A 16-byte-aligned bump heap inside the owned physical frame. The first
    ; 16 bytes preserve the FRM1 ownership marker; no allocation may cross end.
    mov rax, [abs phys_first_free]
    add rax, 16
    mov [abs heap_next], rax
    add rax, 0xff0
    mov [abs heap_end], rax
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
    mov rax, [abs heap_next]
    add rdi, 15
    and rdi, -16
    mov rdx, rax
    add rdx, rdi
    jc .none
    cmp rdx, [abs heap_end]
    ja .none
    mov [abs heap_next], rdx
    ret
.none:
    xor eax, eax
    ret

scheduler_seed:
    ; Two cooperative task descriptors: next, entry, state. They are allocated
    ; from the heap, then traversed through the run queue by scheduler_run.
    mov rdi, 24
    call heap_alloc
    test rax, rax
    jz .fail
    mov rbx, rax
    mov qword [rbx], 0
    mov rax, task_one
    mov [rbx + 8], rax
    mov dword [rbx + 16], 0
    mov [abs run_queue], rbx
    mov rdi, 24
    call heap_alloc
    test rax, rax
    jz .fail
    mov qword [rax], 0
    mov rcx, task_two
    mov [rax + 8], rcx
    mov dword [rax + 16], 0
    mov [rbx], rax
    call scheduler_run
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

isr_default:
    ; Deliberately fail-stop: no interrupted state is resumed before a full
    ; exception-frame ABI exists. Every vector has a present kernel-only gate.
    mov al, 'E'
    out 0xe9, al
    mov al, 'X'
    out 0xe9, al
    mov al, '0'
    out 0xe9, al
    mov al, '6'
    out 0xe9, al
    cli
.halt: hlt
    jmp .halt

align 8
gdt:
    dq 0
    dq 0x00cf9a000000ffff ; 32-bit code
    dq 0x00cf92000000ffff ; 32-bit data
    dq 0x00af9a000000ffff ; 64-bit code
    dq 0x00af92000000ffff ; 64-bit data
gdt_descriptor:
    dw gdt_end - gdt - 1
    dd gdt
gdt_end:
default abs
align 16
idt:
%rep 256
    dw isr_default
    dw 0x18
    db 0
    db 0x8e
    dw 0
    dd 0
    dd 0
%endrep
idt_end:
idt_descriptor:
    dw idt_end - idt - 1
    dq idt
align 8
phys_first_free:
    dq 0
heap_next:
    dq 0
heap_end:
    dq 0
run_queue:
    dq 0
times 512*32-($-$$) db 0
