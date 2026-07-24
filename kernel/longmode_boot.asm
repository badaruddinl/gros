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
    mov al, 'L'
    out 0xe9, al
    mov al, 'M'
    out 0xe9, al
    mov al, '6'
    out 0xe9, al
    mov al, '4'
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
times 512*32-($-$$) db 0
