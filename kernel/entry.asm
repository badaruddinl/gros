start:
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    ; Stable bootstrap-info block: boot drive at 0000:5ffe.
    mov [0x5ffe], dl
    ; Use the BIOS extended-disk protocol in two DMA-safe chunks.  A single
    ; CHS transfer of this kernel would exceed both the 127-sector BIOS limit
    ; and the 64 KiB real-mode DMA boundary; the two contiguous destinations
    ; below keep the stage-2 image complete before the far jump.
    mov si, disk_address_packet
    mov dl, [0x5ffe]
    mov ah, 0x42
    int 0x13
    jc disk_fail
    mov word [disk_address_packet + 4], 0x0000
    ; Continue directly after the first half; this expression must move with
    ; KERNEL_LOAD_SECTORS or the two BIOS transfers overlap and corrupt the
    ; tail of the kernel before long mode starts.
    mov word [disk_address_packet + 6], 0x0800 + KERNEL_LOAD_SECTORS * 16
    mov dword [disk_address_packet + 8], 1 + KERNEL_LOAD_SECTORS / 2
    mov si, disk_address_packet
    mov dl, [0x5ffe]
    mov ah, 0x42
    int 0x13
    jc disk_fail
    xor ax, ax
    mov es, ax
    mov dl, [0x5ffe]
    jmp 0x0000:0x8000
disk_fail:
    cli
.halt: hlt
    jmp .halt
disk_address_packet:
    db 0x10, 0x00
    dw KERNEL_LOAD_SECTORS / 2
    dw 0x8000
    dw 0x0000
    dq 1
times 510-($-$$) db 0
dw 0xaa55

; loaded by sector two, at 0000:8000
section .stage2 start=512 vstart=0x8000
stage2:
    cli
    cld
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
    ; Zero the bootstrap page-table arena at 0x1000..0x7fff.  The first two
    ; 2 MiB leaves are supervisor-only identity mappings; the 4 MiB user base
    ; is a 4 KiB page-table slot that each process owns in its own root.
    xor eax, eax
    mov edi, 0x1000
    mov ecx, 3072
    rep stosd
    ; 0x5ffc..0x60ff contains the BIOS E820 handoff; keep it intact while
    ; clearing the separately placed per-process bootstrap PT at 0x7000.
    mov edi, KERNEL_USER_PT
    mov ecx, 1024
    rep stosd
    mov dword [0x1000], 0x2007 ; user-visible table for the bounded window
    mov dword [0x2000], 0x3007
    mov dword [0x3000], 0x0083 ; 2 MiB identity map, present/write/huge
    mov dword [0x3008], 0x200083 ; supervisor identity map, 2..4 MiB
    mov dword [0x3010], KERNEL_USER_PT | 0x7 ; per-process user PT slot
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
grogan_entry:
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x90000
    cld
    lidt [abs idt_descriptor]
    ; Fill the relocatable base fields of the long-mode TSS descriptor before
    ; loading TR.  NASM keeps the binary flat, so this runtime patch avoids a
    ; link-time address truncation while retaining a real hardware TSS.
    mov rax, tss64
    mov word [abs gdt + 56 + 2], ax
    shr rax, 16
    mov byte [abs gdt + 56 + 4], al
    shr rax, 8
    mov byte [abs gdt + 56 + 7], al
    shr rax, 8
    mov dword [abs gdt + 56 + 8], eax
    mov dword [abs tss64 + 4], 0x90000
    mov word [abs tss64 + 102], tss_end - tss64
    mov ax, TSS_SELECTOR
    ltr ax
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
    mov al, 'G'
    out 0xe9, al
    mov al, 'R'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, '6'
    out 0xe9, al
    mov al, '4'
    out 0xe9, al
    call paging_seed
    call interrupt_controller_seed
    call physical_memory_seed
    call heap_seed
    call scheduler_seed
    call fs_seed
    call storage_seed
    call syscall_seed
    call user_mode_seed
after_user_mode:
    mov al, 'U'
    out 0xe9, al
    mov al, 'S'
    out 0xe9, al
    mov al, 'E'
    out 0xe9, al
    mov al, 'R'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    call shell_start
    sti                         ; IRQ delivery is enabled only after setup.
.wait_for_shell:
    cmp byte [abs shell_done], 1
    je .shell_ready
    hlt
    jmp .wait_for_shell
.shell_ready:
    cli
    ud2                         ; vector 6 must enter isr_invalid_opcode.
    cli
.halt: hlt
    jmp .halt

paging_seed:
    ; Keep the kernel's identity map supervisor-only and expose only a 4 KiB
    ; user slot.  Process roots copy the first two PDEs and replace PDE[2]
    ; with an owned page table, so a user mapping can never reach kernel text,
    ; VGA, or the bootstrap data pages.
    mov dword [abs 0x3000], 0x0083
    mov dword [abs 0x3008], 0x200083
    mov dword [abs 0x3010], KERNEL_USER_PT | 0x7
    mov qword [abs paging_window_end], USER_BASE
    mov al, 'P'
    out 0xe9, al
    mov al, 'G'
    out 0xe9, al
    mov al, 'M'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    ret

zero_page:
    ; RDI is an identity-mapped physical page owned by the caller.
    xor eax, eax
    mov ecx, 512
    rep stosq
    ret

; Create one isolated ring-3 address space from a verified native GWO payload.
; RDI=process object, RSI=pid, RDX=payload, RCX=payload bytes.  Alpha keeps
; one code page, one guard page, one stack page, and a dedicated kernel stack;
; every page-table and data frame is owned by the process id.
