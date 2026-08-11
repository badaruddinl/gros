; GrOS Grogan x86_64 BIOS profile bootstrap.
; The first 16-bit sectors remain the firmware handoff; long_mode is the
; product kernel entry for the bounded x86_64 profile seed.
bits 16
section .boot start=0 vstart=0x7c00

; The bootstrap image is intentionally larger than the original preview.  The
; BIOS loader reads the kernel portion in one bounded transfer; the build then
; appends the persistent GFS2 volume after that transfer window.  Keeping the
; sector count here and in the image builder prevents a partially loaded
; kernel from ever reaching long mode.
%define KERNEL_LOAD_SECTORS 116
%define PAGE_SIZE 0x1000
%define USER_BASE 0x400000
%define USER_CODE 0x400000
%define USER_GUARD 0x401000
%define USER_STACK 0x402000
%define USER_STACK_TOP 0x403000
%define USER_LIMIT 0x40000000
%define VM_BLOB_OFFSET 0x400
%define VM_STACK_BASE (USER_STACK + 0x100)
%define VM_LOCALS_BASE (USER_STACK + 0x600)
%define VM_BUFFER (USER_STACK + 0x900)
%define VM_PC_SLOT USER_STACK
%define VM_SP_SLOT (USER_STACK + 8)
%define VM_STEP_SLOT (USER_STACK + 16)
%define VM_LIMIT_SLOT (USER_STACK + 24)
%define VM_CODE_LIMIT (USER_CODE + VM_BLOB_OFFSET + PAGE_SIZE - VM_BLOB_OFFSET)
%define KERNEL_CR3 0x1000
%define KERNEL_PDPT 0x2000
%define KERNEL_PD 0x3000
%define KERNEL_USER_PT 0x7000
%define TSS_SELECTOR 0x38
%define MAX_FRAMES 768
%define FS_START_LBA 128
%define ATA_PRIMARY_DATA 0x1f0
%define ATA_PRIMARY_SECTOR_COUNT 0x1f2
%define ATA_PRIMARY_LBA0 0x1f3
%define ATA_PRIMARY_DRIVE 0x1f6
%define ATA_PRIMARY_STATUS 0x1f7

; Process object layout.  The object is intentionally fixed-size in Alpha so
; teardown can walk every owned frame without a hidden allocator dependency.
%define PROC_STATE 0
%define PROC_PID 4
%define PROC_PARENT 8
%define PROC_CR3 16
%define PROC_PDPT 24
%define PROC_PD 32
%define PROC_PT 40
%define PROC_CODE 48
%define PROC_STACK 56
%define PROC_KSTACK 64
%define PROC_KTOP 72
%define PROC_CONTEXT 80
%define PROC_RIP 88
%define PROC_RSP 96
%define PROC_FLAGS 104
%define PROC_EXIT_STATUS 108
%define PROC_NEXT 112
%define PROC_HEAP 120
%define PROC_SIZE 128
%define PROC_READY 1
%define PROC_RUNNING 2
%define PROC_BLOCKED 3
%define PROC_EXITED 4

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
    mov ah, 0x02
    mov al, KERNEL_LOAD_SECTORS
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
    cmp r15, PAGE_SIZE - VM_BLOB_OFFSET
    ja .fail
    xor eax, eax
    mov rdi, r12
    mov ecx, PROC_SIZE / 8
    rep stosq

    mov rdi, r13
    call frame_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_CR3], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call frame_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_PDPT], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call frame_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_PD], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call frame_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_PT], rax
    mov rdi, rax
    call zero_page

    mov rdi, r13
    call frame_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_CODE], rax
    mov r8, rax
    mov rdi, r8
    call zero_page

    mov rdi, r13
    call frame_alloc_owned
    test rax, rax
    jz .fail
    mov [r12 + PROC_STACK], rax
    mov r8, rax
    mov rdi, r8
    call zero_page
    mov rdx, USER_CODE + VM_BLOB_OFFSET
    add rdx, r15
    mov [r8 + 24], rdx

    mov rdi, r13
    call frame_alloc_owned
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

    ; PTE[0] is RX code, PTE[1] is the unmapped guard page, PTE[2] is RW
    ; user stack.  A missing PTE therefore becomes a recoverable user fault.
    mov rbx, [r12 + PROC_PT]
    mov rax, [r12 + PROC_CODE]
    or rax, 5
    mov [rbx], rax
    mov rax, [r12 + PROC_STACK]
    or rax, 7
    mov [rbx + 16], rax

    ; The executable page contains the fixed ring-3 GrVM entry followed by
    ; verified GWO2 bytecode.  The VM itself is native bootstrap code; the
    ; program it interprets is always the checked artifact supplied by the
    ; loader, never a source-specific shortcut.
    mov rdi, [r12 + PROC_CODE]
    mov rsi, user_vm_program
    mov ecx, user_vm_program_end - user_vm_program
    rep movsb
    mov rdi, [r12 + PROC_CODE]
    add rdi, VM_BLOB_OFFSET
    mov rsi, r14
    mov ecx, r15d
    rep movsb

    mov dword [r12 + PROC_PID], r13d
    mov dword [r12 + PROC_PARENT], 0
    mov dword [r12 + PROC_STATE], PROC_READY
    mov dword [r12 + PROC_EXIT_STATUS], 0
    mov qword [r12 + PROC_RIP], USER_CODE
    mov qword [r12 + PROC_RSP], USER_STACK_TOP
    mov qword [r12 + PROC_FLAGS], 0x202
    mov qword [r12 + PROC_NEXT], 0
    mov qword [r12 + PROC_HEAP], USER_BASE + 4 * PAGE_SIZE

    ; A timer interrupt from ring 3 returns through this prepared full frame.
    mov r8, [r12 + PROC_KSTACK]
    lea r9, [r8 + PAGE_SIZE]
    mov [r12 + PROC_KTOP], r9
    sub r9, 160
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
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

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
    mov dword [r12 + PROC_STATE], PROC_EXITED
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

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
    mov rdx, user_payload_kernel
    mov ecx, [abs user_payload_size]
    mov rdi, process_one
    mov rsi, 1
    call process_create
    mov rdx, user_payload_kernel
    mov ecx, [abs user_payload_size]
    mov rdi, process_two
    mov rsi, 2
    call process_create
    mov qword [abs process_one + PROC_NEXT], process_two
    mov qword [abs process_two + PROC_NEXT], process_one
    mov qword [abs current_process], process_one
    mov dword [abs process_one + PROC_STATE], PROC_RUNNING
    mov rax, [abs process_one + PROC_CR3]
    mov cr3, rax
    mov rax, [abs process_one + PROC_KTOP]
    mov [abs tss64 + 4], eax
    mov dword [abs tss64 + 8], 0
    mov rcx, USER_CODE
    mov r11, 0x202
    mov rsp, USER_STACK_TOP
    db 0x48, 0x0f, 0x07       ; SYSRETQ

gwo_load_user:
    ; GWO2 v2 Alpha has a 32-byte header and one 16-byte bytecode section.
    ; Every size, target, checksum, instruction boundary, import signature,
    ; and stack effect is checked before any user address space is created.
    cmp dword [abs user_gwo_image], 0x324f5747 ; GWO2
    jne .fail
    cmp word [abs user_gwo_image + 4], 2
    jne .fail
    cmp word [abs user_gwo_image + 6], 1
    jne .fail
    cmp word [abs user_gwo_image + 8], 1
    jne .fail
    cmp word [abs user_gwo_image + 10], 0
    jne .fail
    cmp dword [abs user_gwo_image + 12], 32
    jne .fail
    cmp dword [abs user_gwo_image + 16], 1
    jne .fail
    cmp dword [abs user_gwo_image + 20], 0
    jne .fail
    mov r8d, [abs user_gwo_image + 24]
    test r8d, r8d
    jz .fail
    cmp r8d, PAGE_SIZE - VM_BLOB_OFFSET
    ja .fail
    mov eax, r8d
    add eax, 48
    cmp eax, user_gwo_image_end - user_gwo_image
    jne .fail
    cmp dword [abs user_gwo_image + 32], 1
    jne .fail
    cmp dword [abs user_gwo_image + 36], 48
    jne .fail
    cmp dword [abs user_gwo_image + 40], r8d
    jne .fail
    mov rdi, user_gwo_image + 32
    mov esi, r8d
    add rsi, 16
    call gwo_fnv32
    cmp eax, [abs user_gwo_image + 28]
    jne .fail
    mov rdi, user_gwo_image + 48
    mov esi, r8d
    call gwo_fnv32
    cmp eax, [abs user_gwo_image + 44]
    jne .fail
    mov rsi, user_gwo_image + 48
    mov rdi, user_payload_kernel
    mov ecx, r8d
    rep movsb
    mov [abs user_payload_size], r8d
    mov rdi, user_payload_kernel
    mov esi, r8d
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
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

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
    mov ecx, PAGE_SIZE
    rep stosb
    xor r8d, r8d
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
.not_arithmetic:
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
    jmp .bad
.const:
    mov r10d, 5
    mov r11d, 1
    jmp .finish
.local_load:
    mov r10d, 2
    movzx edx, byte [r12 + r8 + 1]
    cmp edx, 64
    jae .bad
    mov r11d, 1
    jmp .finish
.local_store:
    mov r10d, 2
    movzx edx, byte [r12 + r8 + 1]
    cmp edx, 64
    jae .bad
    mov r11d, -1
    jmp .finish
.arithmetic:
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
    jne .bad
    test ecx, ecx
    jnz .bad
    jmp .finish
.import_one:
    cmp ecx, 1
    jne .bad
    mov r11d, -1
    jmp .finish
.return:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.halt:
    mov r10d, 1
.finish:
    mov eax, r8d
    add eax, r10d
    jc .bad
    cmp eax, r13d
    ja .bad
    test r11d, r11d
    jns .effect_add
    mov edx, r11d
    neg edx
    cmp r9d, edx
    jb .bad
.effect_add:
    add r9d, r11d
    cmp r9d, 128
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
    cmp eax, 1                  ; console_read (non-blocking Alpha seed)
    je .read
    cmp eax, 2                  ; console_write
    je .write
    cmp eax, 8                  ; mem_grow
    je .mem_grow
    cmp eax, 0x0b               ; process_exit
    je .exit
    cmp eax, 0x0c               ; task_yield
    je .yield
    mov rax, -38                ; -ENOSYS
    jmp .return_user
.kernel_bad:
    cli
.halt: hlt
    jmp .halt
.read:
    xor eax, eax
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
    mov rdi, rbx
    mov rsi, r8
    call process_map_page
    test eax, eax
    jz .mem_fail
    mov [rbx + PROC_HEAP], r9
    mov rax, r8
    jmp .return_user
.mem_return:
    mov rax, [rbx + PROC_HEAP]
    jmp .return_user
.mem_fail:
    mov rax, -12                ; -ENOMEM
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
    jmp process_yield_current
.return_user:
    mov rbx, [abs current_process]
    mov rcx, [rbx + PROC_RIP]
    mov r11, [rbx + PROC_FLAGS]
    mov rsp, [rbx + PROC_RSP]
    db 0x48, 0x0f, 0x07       ; SYSRETQ

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
    mov rcx, [rbx + PROC_RIP]
    mov r11, [rbx + PROC_FLAGS]
    mov rsp, [rbx + PROC_RSP]
    db 0x48, 0x0f, 0x07       ; SYSRETQ

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
    mov rbx, [abs current_process]
    mov rcx, [rbx + PROC_RIP]
    mov r11, [rbx + PROC_FLAGS]
    mov rsp, [rbx + PROC_RSP]
    db 0x48, 0x0f, 0x07
.kernel_shell:
    mov rsp, 0x90000
    mov rdi, rbx
    call process_reap
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

process_timer_tick:
    ; RDI=register-save pointer created by irq_timer_stub.  Preserve the
    ; interrupted frame in the current process, then return the next process
    ; frame to the same stub.  The stub's pop/iret sequence is therefore
    ; identical for a fresh process and a preempted one.
    mov rbx, [abs current_process]
    test rbx, rbx
    jz .same
    mov [rbx + PROC_CONTEXT], rdi
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

fs_seed:
    ; Read-only boot-resident filesystem: superblock plus one root entry. Its
    ; payload is copied through heap_alloc, not accessed through a raw pointer.
    cmp dword [abs fs_image], 0x31534647 ; "GFS1"
    jne .fail
    cmp dword [abs fs_entry], 0x54494e49 ; root name "INIT"
    jne .fail
    mov edi, [abs fs_entry + 4]
    cmp edi, 4
    jne .fail
    mov rdi, 16
    call heap_alloc
    test rax, rax
    jz .fail
    mov rdi, rax
    mov rsi, fs_payload
    mov ecx, 4
    rep movsb
    cmp dword [rdi - 4], 0x53465247 ; "GRFS"
    jne .fail
    lea rax, [rdi - 4]
    mov [abs fs_payload_copy], rax
    mov byte [abs fs_loaded], 1
    mov al, 'F'
    out 0xe9, al
    mov al, 'S'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

ata_wait_drq:
    ; Poll BSY/ERR/DRQ with a finite budget.  A device error or timeout is a
    ; normal block-layer failure, never an infinite interrupt-disabled loop.
    mov dx, ATA_PRIMARY_STATUS
    mov ecx, 0x100000
.poll:
    in al, dx
    test al, 0x80
    jnz .again
    test al, 1
    jnz .fail
    test al, 8
    jnz .ready
.again:
    dec ecx
    jnz .poll
.fail:
    xor eax, eax
    ret
.ready:
    mov eax, 1
    ret

ata_wait_idle:
    mov dx, ATA_PRIMARY_STATUS
    mov ecx, 0x100000
.poll:
    in al, dx
    test al, 0x80
    jnz .again
    test al, 1
    jnz .fail
    mov eax, 1
    ret
.again:
    dec ecx
    jnz .poll
.fail:
    xor eax, eax
    ret

ata_select_lba:
    ; RDI=LBA28 sector.  The command-specific caller writes 20h/30h after
    ; this register setup.
    mov r8, rdi
    mov dx, ATA_PRIMARY_DRIVE
    mov al, 0xe0
    mov rcx, r8
    shr rcx, 24
    and cl, 0x0f
    or al, cl
    out dx, al
    mov dx, ATA_PRIMARY_SECTOR_COUNT
    mov al, 1
    out dx, al
    mov dx, ATA_PRIMARY_LBA0
    mov rax, r8
    out dx, al
    inc dx
    shr rax, 8
    out dx, al
    inc dx
    shr rax, 8
    out dx, al
    ret

ata_probe:
    cli
    mov dx, ATA_PRIMARY_DRIVE
    mov al, 0xa0
    out dx, al
    xor al, al
    mov dx, ATA_PRIMARY_SECTOR_COUNT
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    inc dx
    out dx, al
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0xec
    out dx, al
    in al, dx
    test al, al
    jz .fail
    call ata_wait_drq
    test eax, eax
    jz .fail
    mov dx, ATA_PRIMARY_DATA
    mov rdi, ata_identify_buffer
    mov ecx, 256
    rep insw
    movzx eax, word [abs ata_identify_buffer + 120]
    movzx edx, word [abs ata_identify_buffer + 122]
    shl rdx, 16
    or rax, rdx
    test rax, rax
    jz .fail
    mov [abs ata_capacity], rax
    mov byte [abs ata_ready], 1
    mov eax, 1
    ret
.fail:
    mov byte [abs ata_ready], 0
    xor eax, eax
    ret

ata_block_read:
    ; RDI=relative GFS2 block, RSI=512-byte kernel destination.
    cmp byte [abs ata_ready], 1
    jne .fail
    mov r8, [abs ata_capacity]
    cmp r8, FS_START_LBA
    jbe .fail
    sub r8, FS_START_LBA
    cmp rdi, r8
    jae .fail
    add rdi, FS_START_LBA
    push rsi
    call ata_select_lba
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0x20
    out dx, al
    call ata_wait_drq
    test eax, eax
    jz .pop_fail
    mov dx, ATA_PRIMARY_DATA
    pop rdi
    mov ecx, 256
    rep insw
    mov eax, 1
    ret
.pop_fail:
    pop rsi
.fail:
    xor eax, eax
    ret

ata_block_write:
    ; RDI=relative GFS2 block, RSI=512-byte kernel source.
    cmp byte [abs ata_ready], 1
    jne .fail
    mov r8, [abs ata_capacity]
    cmp r8, FS_START_LBA
    jbe .fail
    sub r8, FS_START_LBA
    cmp rdi, r8
    jae .fail
    add rdi, FS_START_LBA
    push rsi
    call ata_select_lba
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0x30
    out dx, al
    call ata_wait_drq
    test eax, eax
    jz .pop_fail
    mov dx, ATA_PRIMARY_DATA
    pop rsi
    mov ecx, 256
    rep outsw
    mov dx, ATA_PRIMARY_STATUS
    mov al, 0xe7
    out dx, al
    call ata_wait_idle
    ret
.pop_fail:
    pop rsi
.fail:
    xor eax, eax
    ret

gfs_checksum:
    ; RDI=superblock bytes.  The host and kernel use the same FNV-1a-32
    ; checksum over the first 52 bytes.
    mov eax, 2166136261
    mov ecx, 52
.sum:
    movzx edx, byte [rdi]
    xor eax, edx
    imul eax, 16777619
    inc rdi
    dec ecx
    jnz .sum
    ret

gfs_validate_super:
    cmp dword [rdi], 0x32534647 ; GFS2
    jne .bad
    cmp word [rdi + 4], 2
    jne .bad
    cmp word [rdi + 6], 512
    jne .bad
    cmp dword [rdi + 56], 0x324d5443 ; CMT2
    jne .bad
    push rdi
    call gfs_checksum
    pop rdi
    cmp eax, [rdi + 52]
    jne .bad
    mov rax, [rdi + 16]
    test rax, rax
    jz .bad
    mov r8, [abs ata_capacity]
    cmp rax, r8
    ja .bad
    cmp dword [rdi + 32], 1
    jne .bad
    cmp dword [rdi + 44], 32
    jne .bad
    cmp dword [rdi + 48], 1
    jne .bad
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

gfs_mount:
    xor edi, edi
    mov rsi, gfs_super_buffer
    call ata_block_read
    test eax, eax
    jz .bad
    mov rdi, gfs_super_buffer
    call gfs_validate_super
    mov ebx, eax
    xor edi, edi
    mov rsi, gfs_recovery_buffer
    mov edi, 1
    call ata_block_read
    test eax, eax
    jz .choose_primary
    mov rdi, gfs_recovery_buffer
    call gfs_validate_super
    test eax, eax
    jz .choose_primary
    cmp ebx, 1
    jne .choose_recovery
    mov rax, [abs gfs_recovery_buffer + 8]
    cmp rax, [abs gfs_super_buffer + 8]
    jbe .choose_primary
.choose_recovery:
    mov rsi, gfs_recovery_buffer
    mov rdi, gfs_super_buffer
    mov ecx, 64
    rep movsq
.choose_primary:
    mov rdi, gfs_super_buffer
    call gfs_validate_super
    test eax, eax
    jz .bad
    mov rax, [abs gfs_super_buffer + 16]
    mov [abs gfs_total_blocks], rax
    mov byte [abs gfs_mount_valid], 1
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

storage_seed:
    call ata_probe
    test eax, eax
    jz .fail
    call gfs_mount
    test eax, eax
    jz .fail
    mov al, 'A'
    out 0xe9, al
    mov al, 'T'
    out 0xe9, al
    mov al, 'A'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    mov al, 'G'
    out 0xe9, al
    mov al, 'F'
    out 0xe9, al
    mov al, 'S'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, 'K'
    out 0xe9, al
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

shell_start:
    mov rsi, shell_banner
    call console_write_string
    mov rsi, shell_prompt
    call console_write_string
    ret

keyboard_handle_scancode:
    ; Set-1 make codes for the small command vocabulary. Break codes are
    ; filtered by irq_keyboard_stub before this routine is called.
    cmp ebx, 0x1c
    je .enter
    cmp ebx, 0x0e
    je .backspace
    cmp ebx, 0x1e
    je .a
    cmp ebx, 0x30
    je .b
    cmp ebx, 0x2e
    je .c
    cmp ebx, 0x12
    je .e
    cmp ebx, 0x23
    je .h
    cmp ebx, 0x25
    je .k
    cmp ebx, 0x26
    je .l
    cmp ebx, 0x32
    je .m
    cmp ebx, 0x18
    je .o
    cmp ebx, 0x19
    je .p
    cmp ebx, 0x13
    je .r
    cmp ebx, 0x1f
    je .s
    cmp ebx, 0x14
    je .t
    cmp ebx, 0x2f
    je .v
    cmp ebx, 0x2c
    je .z
    ret
.a:
    mov al, 'a'
    jmp .print
.b:
    mov al, 'b'
    jmp .print
.c:
    mov al, 'c'
    jmp .print
.e:
    mov al, 'e'
    jmp .print
.h:
    mov al, 'h'
    jmp .print
.k:
    mov al, 'k'
    jmp .print
.l:
    mov al, 'l'
    jmp .print
.m:
    mov al, 'm'
    jmp .print
.o:
    mov al, 'o'
    jmp .print
.p:
    mov al, 'p'
    jmp .print
.r:
    mov al, 'r'
    jmp .print
.s:
    mov al, 's'
    jmp .print
.t:
    mov al, 't'
    jmp .print
.v:
    mov al, 'v'
    jmp .print
.z: mov al, 'z'
.print:
    mov dl, [abs shell_len]
    cmp dl, 63
    jae .done
    mov rsi, shell_buffer
    movzx edx, dl
    mov [rsi + rdx], al
    inc dl
    mov [abs shell_len], dl
    movzx edx, dl
    mov byte [rsi + rdx], 0
    call console_write_char
.done:
    ret
.backspace:
    cmp byte [abs shell_len], 0
    je .done
    dec byte [abs shell_len]
    movzx edx, byte [abs shell_len]
    mov rsi, shell_buffer
    mov byte [rsi + rdx], 0
    mov al, 8
    call console_write_char
    mov al, ' '
    call console_write_char
    mov al, 8
    call console_write_char
    ret
.enter:
    mov al, 13
    call console_write_char
    mov al, 10
    call console_write_char
    call shell_execute
    mov byte [abs shell_len], 0
    mov byte [abs shell_buffer], 0
    cmp byte [abs shell_done], 1
    je .done
    mov rsi, shell_prompt
    call console_write_string
    ret

shell_execute:
    mov rsi, shell_buffer
    mov rdi, cmd_help
    mov ecx, 4
    call shell_match
    test al, al
    jnz .help
    mov rsi, shell_buffer
    mov rdi, cmd_ls
    mov ecx, 2
    call shell_match
    test al, al
    jnz .ls
    mov rsi, shell_buffer
    mov rdi, cmd_cat
    mov ecx, 3
    call shell_match
    test al, al
    jnz .cat
    mov rsi, shell_buffer
    mov rdi, cmd_mem
    mov ecx, 3
    call shell_match
    test al, al
    jnz .mem
    mov rsi, shell_buffer
    mov rdi, cmd_tasks
    mov ecx, 5
    call shell_match
    test al, al
    jnz .tasks
    mov rsi, shell_buffer
    mov rdi, cmd_reboot
    mov ecx, 6
    call shell_match
    test al, al
    jnz .reboot
    mov rsi, shell_unknown
    call console_write_string
    ret
.help:
    mov rsi, shell_help
    call console_write_string
    ret
.ls:
    cmp byte [abs fs_loaded], 1
    jne .fs_fail
    mov rsi, fs_entry
    mov ecx, 4
    call console_write_bytes
    mov rsi, shell_line_end
    call console_write_string
    ret
.cat:
    cmp byte [abs fs_loaded], 1
    jne .fs_fail
    mov rsi, fs_entry
    mov ecx, 4
    call console_write_bytes
    mov rsi, shell_cat_separator
    call console_write_string
    mov rsi, [abs fs_payload_copy]
    mov ecx, [abs fs_entry + 4]
    call console_write_bytes
    mov rsi, shell_line_end
    call console_write_string
    ret
.mem:
    mov rsi, shell_mem
    call console_write_string
    ret
.tasks:
    mov rsi, shell_tasks
    call console_write_string
    ret
.reboot:
    mov rsi, shell_reboot
    call console_write_string
    mov byte [abs shell_done], 1
    ret
.fs_fail:
    mov rsi, shell_unknown
    call console_write_string
    ret

shell_match:
    xor eax, eax
.loop:
    test ecx, ecx
    jz .check_end
    mov al, [rsi]
    cmp al, [rdi]
    jne .no
    inc rsi
    inc rdi
    dec ecx
    jmp .loop
.check_end:
    cmp byte [rsi], 0
    jne .no
    mov al, 1
    ret
.no:
    xor eax, eax
    ret

console_write_string:
    push rsi
.next:
    mov al, [rsi]
    inc rsi
    test al, al
    jz .done
    call console_write_char
    jmp .next
.done:
    pop rsi
    ret

console_write_bytes:
    push rsi
.next:
    test ecx, ecx
    jz .done
    mov al, [rsi]
    inc rsi
    dec ecx
    call console_write_char
    jmp .next
.done:
    pop rsi
    ret

console_write_char:
    push rbx
    push rcx
    push rdx
    mov bl, al
    out 0xe9, al
    mov rcx, [abs vga_cursor]
    mov rdx, 0xb8000
    add rdx, rcx
    mov [rdx], bl
    mov byte [rdx + 1], 0x07
    add rcx, 2
    cmp rcx, 4000
    jb .store
    xor ecx, ecx
.store:
    mov [abs vga_cursor], rcx
    pop rdx
    pop rcx
    pop rbx
    ret

; Ring-3 GrVM entry.  The kernel copies this fixed interpreter into each
; process code page and places the verified GWO2 bytecode at VM_BLOB_OFFSET.
; VM state is held in the user stack page so SYSCALL can freely clobber caller
; registers while the state is reloaded after each console import.
user_vm_program_marker:
    db 'V', 'M', 'P', '2'
user_vm_program:
    xor r13d, r13d
    xor r14d, r14d
    mov r12, USER_CODE + VM_BLOB_OFFSET
    xor eax, eax
    mov rdi, VM_STACK_BASE
    mov ecx, 192
    rep stosq
.loop:
    inc r14
    cmp r14, 1000000
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
    jmp .fail
.const:
    cmp r13, 128
    jae .fail
    movsxd rax, dword [r12]
    add r12, 4
    mov [VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.load_local:
    movzx eax, byte [r12]
    inc r12
    cmp eax, 64
    jae .fail
    cmp r13, 128
    jae .fail
    mov rax, [abs VM_LOCALS_BASE + rax * 8]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
    jmp .loop
.store_local:
    cmp r13, 1
    jb .fail
    movzx eax, byte [r12]
    inc r12
    cmp eax, 64
    jae .fail
    dec r13
    mov rdx, [abs VM_STACK_BASE + r13 * 8]
    mov [abs VM_LOCALS_BASE + rax * 8], rdx
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
    jmp .fail
.add:
    add rbx, rax
    mov rax, rbx
    jmp .binary_push
.sub:
    sub rbx, rax
    mov rax, rbx
    jmp .binary_push
.mul:
    imul rbx, rax
    mov rax, rbx
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
    cmp eax, 1
    je .import_print
    cmp eax, 2
    je .import_exit
    cmp eax, 3
    je .import_newline
    jmp .fail
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
    jmp .loop
.import_newline:
    test ebx, ebx
    jnz .fail
    mov byte [abs VM_BUFFER], 10
    mov eax, 2
    mov edi, VM_BUFFER
    mov esi, 1
    syscall
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    xor edi, edi
    test r13, r13
    jz .return_syscall
    dec r13
    mov edi, [abs VM_STACK_BASE + r13 * 8]
.return_syscall:
    mov eax, 0x0b
    syscall
    jmp .fail
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
gdt:
    dq 0
    dq 0x00cf9a000000ffff ; 32-bit code
    dq 0x00cf92000000ffff ; 32-bit data
    dq 0x00af9a000000ffff ; 64-bit code
    dq 0x00af92000000ffff ; 64-bit data
    dq 0x00cff2000000ffff ; DPL3 data, SYSRET SS = 2bh
    dq 0x00affa000000ffff ; DPL3 64-bit code, SYSRET CS = 33h
    ; 64-bit available TSS (selector 38h).  The descriptor is deliberately
    ; adjacent to the user descriptors so STAR/SYSRET selectors stay stable.
    dw tss_end - tss64 - 1
    dw 0
    db 0
    db 0x89
    db (tss_end - tss64 - 1) >> 16
    db 0
    dd 0
    dd 0
gdt_descriptor:
    dw gdt_end - gdt - 1
    dd gdt
gdt_end:
default abs
align 16
idt:
%assign idt_vector 0
%rep 256
%if idt_vector = 6
    dw isr_invalid_opcode
%elif idt_vector = 14
    dw isr_page_fault
%elif idt_vector = 32
    dw irq_timer_stub
%elif idt_vector = 33
    dw irq_keyboard_stub
%else
    dw isr_default
%endif
    dw 0x18
    db 0
    db 0x8e
    dw 0
    dd 0
    dd 0
%assign idt_vector idt_vector + 1
%endrep
idt_end:
idt_descriptor:
    dw idt_end - idt - 1
    dq idt
align 16
tss64:
    times 104 db 0
tss_end:
align 8
phys_first_free:
    dq 0
phys_frame_count:
    dd 0
align 8
frame_pool:
    times MAX_FRAMES dq 0
frame_used:
    times MAX_FRAMES db 0
frame_owner:
    times MAX_FRAMES dd 0
paging_window_end:
    dq 0
heap_base:
    dq 0
heap_slot_count:
    dd 0
heap_probe_one:
    dq 0
align 8
heap_bitmap:
    times 256 db 0
heap_next:
    dq 0
heap_end:
    dq 0
run_queue:
    dq 0
scheduler_task_one:
    dq 0
scheduler_task_two:
    dq 0
scheduler_current:
    dq 0
scheduler_kernel_context:
    dq 0
timer_seen:
    db 0
last_scancode:
    db 0
fs_loaded:
    db 0
align 8
fs_payload_copy:
    dq 0
user_syscall_seen:
    db 0
user_done:
    db 0
align 8
user_saved_rip:
    dq 0
user_saved_flags:
    dq 0
user_saved_rsp:
    dq 0
align 16
process_one:
    times PROC_SIZE db 0
process_two:
    times PROC_SIZE db 0
current_process:
    dq 0
user_payload_size:
    dd 0
align 8
gwo2_boundaries:
    times PAGE_SIZE db 0
ata_ready:
    db 0
gfs_mount_valid:
    db 0
align 8
ata_capacity:
    dq 0
gfs_total_blocks:
    dq 0
align 512
ata_identify_buffer:
    times 512 db 0
gfs_super_buffer:
    times 512 db 0
gfs_recovery_buffer:
    times 512 db 0
align 4096
user_payload_kernel:
    times PAGE_SIZE db 0
shell_len:
    db 0
shell_done:
    db 0
vga_cursor:
    dq 0
shell_buffer:
    times 64 db 0
shell_banner:
    db 13, 10, 'GrOS x86_64', 13, 10, 0
shell_prompt:
    db 'Grogan> ', 0
shell_help:
    db 'help ls cat mem tasks reboot', 13, 10, 0
shell_line_end:
    db 13, 10, 0
shell_cat_separator:
    db ': ', 0
shell_mem:
    db 'FRAMES HEAP PAGES', 13, 10, 0
shell_tasks:
    db 'T1 T2', 13, 10, 0
shell_reboot:
    db 'REBOOT', 13, 10, 0
shell_unknown:
    db '?', 13, 10, 0
cmd_help:
    db 'help', 0
cmd_ls:
    db 'ls', 0
cmd_cat:
    db 'cat', 0
cmd_mem:
    db 'mem', 0
cmd_tasks:
    db 'tasks', 0
cmd_reboot:
    db 'reboot', 0
align 16
user_gwo_image:
    incbin "build/generated/grogan-user.gwo"
user_gwo_image_end:
align 16
fs_image:
    dd 0x31534647 ; GFS1
    dd 1          ; root-entry count
fs_entry:
    dd 0x54494e49 ; INIT
    dd 4          ; payload size
    dq fs_payload
fs_payload:
    db 'GRFS'
times 512*KERNEL_LOAD_SECTORS-($-$$) db 0
