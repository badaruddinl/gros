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
%define KERNEL_LOAD_SECTORS 192
%define PAGE_SIZE 0x1000
%define USER_BASE 0x400000
%define USER_CODE 0x400000
%define MAX_PAYLOAD_PAGES 3
%define MAX_PAYLOAD_BYTES (MAX_PAYLOAD_PAGES * PAGE_SIZE)
%define MAX_GWO_IMAGE_BYTES (MAX_PAYLOAD_BYTES + 48)
%define USER_GUARD (USER_CODE + VM_BLOB_OFFSET + MAX_PAYLOAD_BYTES)
%define USER_STACK (USER_GUARD + PAGE_SIZE)
%define USER_STACK_TOP (USER_STACK + PAGE_SIZE)
%define VM_RUNTIME_BASE USER_STACK_TOP
%define USER_LIMIT 0x40000000
; Keep the fixed GrVM entry and the verified bytecode in separate user pages.
; The interpreter has grown beyond the original 0x400-byte inline prefix;
; sharing a page would let the payload overwrite its native dispatch loop.
%define VM_BLOB_OFFSET 0x1000
%define VM_STACK_BASE (USER_STACK + 0x80)
%define VM_FRAME_BASE VM_RUNTIME_BASE
%define VM_FRAME_STRIDE 2080
%define VM_FRAME_LOCALS 24
%define VM_FRAME_COUNT 64
%define VM_FRAME_END (VM_FRAME_BASE + VM_FRAME_COUNT * VM_FRAME_STRIDE)
%define VM_FRAME_LIMIT VM_FRAME_END
; Hosted GrVM allocates byte constants from its 1 MiB memory arena.  The
; self-hosting compiler emits literals inside loops, so reserve a private
; 32-page constant arena after the frame records and keep the process heap
; above both regions.
%define VM_CONST_PAGES 32
%define VM_CONST_BASE ((VM_FRAME_END + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1))
%define VM_CONST_LIMIT (VM_CONST_BASE + VM_CONST_PAGES * PAGE_SIZE)
%define VM_RUNTIME_PAGES ((VM_CONST_LIMIT - VM_RUNTIME_BASE) >> 12)
%define VM_RUNTIME_END VM_CONST_LIMIT
%define VM_BUFFER (USER_STACK + 0xd80)
%define VM_CONST_CURSOR (VM_BUFFER + 0x200)
%define VM_INSTRUCTION_LIMIT 100000000
%define VM_PC_SLOT USER_STACK
%define VM_SP_SLOT (USER_STACK + 8)
%define VM_STEP_SLOT (USER_STACK + 16)
%define VM_LIMIT_SLOT (USER_STACK + 24)
%define VM_FP_SLOT (USER_STACK + 32)
%define VM_ENTRY_SLOT (USER_STACK + 40)
%define VM_CODE_LIMIT (USER_CODE + VM_BLOB_OFFSET + MAX_PAYLOAD_BYTES)
%define KERNEL_CR3 0x1000
%define KERNEL_PDPT 0x2000
%define KERNEL_PD 0x3000
%define KERNEL_USER_PT 0x7000
%define TSS_SELECTOR 0x38
%define MAX_FRAMES 768
%define FS_START_LBA 224
%define GFS_MAX_FILE_BYTES 65536
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
%define PROC_HANDLE 128
%define PROC_OFFSET 136
%define PROC_INODE 144
%define PROC_FILE_SIZE 152
%define PROC_PAYLOAD_PAGES 160
%define PROC_ENTRY 168
%define PROC_SIZE 176
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
    mov word [disk_address_packet + 6], 0x1400
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
    call frame_alloc_owned
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
    mov eax, [r12 + PROC_ENTRY]
    mov [r8 + 40], eax

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
    call frame_alloc_owned
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
    test eax, eax
    jz .load_fail
    mov rdx, user_payload_kernel
    mov ecx, [abs user_payload_size]
    mov rdi, process_one
    mov rsi, 1
    call process_create
    mov rdi, user_helper_image
    mov esi, user_helper_image_end - user_helper_image
    call gwo_load_image
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
.load_fail:
    cli
.halt: hlt
    jmp .halt

gwo_load_user:
    mov rdi, user_gwo_image
    mov esi, user_gwo_image_end - user_gwo_image
    jmp gwo_load_image

gwo_load_image:
    ; GWO2 v2 Alpha has a 32-byte header and one 16-byte bytecode section.
    ; Every size, target, checksum, instruction boundary, import signature,
    ; and stack effect is checked before any user address space is created.
    push r12
    push r13
    mov r12, rdi
    mov r13d, esi
    cmp r13d, 48
    jb .fail
    cmp dword [r12], 0x324f5747 ; GWO2
    jne .fail
    cmp word [r12 + 4], 2
    jne .fail
    cmp word [r12 + 6], 1
    jne .fail
    cmp word [r12 + 8], 1
    jne .fail
    cmp word [r12 + 10], 0
    jne .fail
    cmp dword [r12 + 12], 32
    jne .fail
    cmp dword [r12 + 16], 1
    jne .fail
    mov eax, [r12 + 20]
    mov r8d, [r12 + 24]
    test r8d, r8d
    jz .fail
    cmp eax, r8d
    jae .fail
    mov [abs user_payload_entry], eax
    cmp r8d, MAX_PAYLOAD_BYTES
    ja .fail
    mov eax, r8d
    add eax, 48
    cmp eax, r13d
    jne .fail
    cmp dword [r12 + 32], 1
    jne .fail
    cmp dword [r12 + 36], 48
    jne .fail
    cmp dword [r12 + 40], r8d
    jne .fail
    lea rdi, [r12 + 32]
    mov esi, r8d
    add rsi, 16
    call gwo_fnv32
    cmp eax, [r12 + 28]
    jne .fail
    lea rdi, [r12 + 48]
    mov esi, r8d
    call gwo_fnv32
    cmp eax, [r12 + 44]
    jne .fail
    lea rsi, [r12 + 48]
    mov rdi, user_payload_kernel
    mov ecx, r8d
    rep movsb
    mov [abs user_payload_size], r8d
    mov rdi, user_payload_kernel
    mov esi, r8d
    mov edx, [abs user_payload_entry]
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
    mov eax, 1
    pop r13
    pop r12
    ret
.fail:
    xor eax, eax
    pop r13
    pop r12
    ret

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
    mov ecx, MAX_PAYLOAD_BYTES
    rep stosb
    xor r8d, r8d
    mov r11d, 0xff
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
    cmp eax, 22
    je .arithmetic
.not_arithmetic:
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
    jmp .bad
.const:
    mov r10d, 5
    mov r11d, 1
    jmp .finish
.local_load:
    mov r10d, 2
    movzx edx, byte [r12 + r8 + 1]
    cmp edx, 255
    jae .bad
    mov r11d, 1
    jmp .finish
.local_store:
    mov r10d, 2
    movzx edx, byte [r12 + r8 + 1]
    cmp edx, 255
    jae .bad
    mov r11d, -1
    jmp .finish
.arithmetic:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.byte_const:
    movzx edx, byte [r12 + r8 + 1]
    lea r10d, [edx + 2]
    mov r11d, 1
    jmp .finish
.byte_load:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.byte_store:
    mov r10d, 1
    mov r11d, -3
    jmp .finish
.duplicate:
    mov r10d, 1
    mov r11d, 1
    jmp .finish
.drop:
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
    je .import_zero
    cmp edx, 4
    je .import_two_result
    cmp edx, 5
    je .import_two_result
    cmp edx, 6
    je .import_three_result
    cmp edx, 7
    je .import_three_result
    cmp edx, 8
    je .import_one_zero
    cmp edx, 9
    je .import_two_zero
    cmp edx, 10
    je .import_one_zero
    cmp edx, 11
    je .import_one_zero
    cmp edx, 12
    je .import_one_zero
    cmp edx, 13
    je .import_two_void
    cmp edx, 14
    je .import_zero
    cmp edx, 15
    je .import_two_result
    cmp edx, 16
    je .import_one_result
    jmp .bad
.import_one:
    cmp ecx, 1
    jne .bad
    mov r11d, -1
    jmp .finish
.import_zero:
    test ecx, ecx
    jnz .bad
    jmp .finish
.import_two_result:
    cmp ecx, 2
    jne .bad
    mov r11d, -1
    jmp .finish
.import_three_result:
    cmp ecx, 3
    jne .bad
    mov r11d, -2
    jmp .finish
.import_one_zero:
    cmp ecx, 1
    jne .bad
    jmp .finish
.import_two_zero:
    cmp ecx, 2
    jne .bad
    mov r11d, -1
    jmp .finish
.import_two_void:
    cmp ecx, 2
    jne .bad
    mov r11d, -2
    jmp .finish
.import_one_result:
    cmp ecx, 1
    jne .bad
    xor r11d, r11d
    jmp .finish
.return:
    mov r10d, 1
    mov r11d, -1
    jmp .finish
.halt:
    mov r10d, 1
.return_void:
    mov r10d, 1
    jmp .finish
.call:
    mov r10d, 5
    movzx edx, byte [r12 + r8 + 3]
    movzx ecx, byte [r12 + r8 + 4]
    cmp edx, 255
    ja .bad
    cmp ecx, 1
    ja .bad
    mov r11d, ecx
    sub r11d, edx
.finish:
    mov eax, r8d
    add eax, r10d
    jc .bad
    cmp eax, r13d
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
    cmp eax, 15
    je .boundary_byte_const
    cmp eax, 16
    je .boundary_length
    cmp eax, 17
    je .boundary_length
    cmp eax, 18
    je .boundary_length
    cmp eax, 19
    je .boundary_length
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
    cmp eax, 20
    je .boundary_call
    cmp eax, 21
    je .boundary_length
    cmp eax, 22
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
.boundary_byte_const:
    movzx r10d, byte [r12 + r8 + 1]
    add r10d, 2
    jmp .boundary_length
.boundary_call:
    mov r10d, 5
    movzx ecx, word [r12 + r8 + 1]
    cmp ecx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rcx], 1
    jne .bad
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
.cfg_init:
    ; Re-run the verified instruction map as a small forward data-flow
    ; analysis.  A linear stack counter is insufficient for if/else and loop
    ; joins: every reachable instruction receives exactly one operand depth.
    mov rdi, gwo2_depths
    mov al, 0xff
    mov ecx, MAX_PAYLOAD_BYTES
    rep stosb
    mov edx, [abs user_payload_entry]
    cmp edx, r13d
    jae .bad
    mov byte [gwo2_depths + rdx], 0
.cfg_pass:
    xor r10d, r10d              ; changed in this pass
    xor r8d, r8d
.cfg_scan:
    cmp r8d, r13d
    jae .cfg_done_scan
    movzx eax, byte [gwo2_depths + r8]
    cmp eax, 0xff
    je .cfg_next
    cmp byte [gwo2_boundaries + r8], 1
    jne .bad
    mov r9d, eax                ; input depth
    movzx eax, byte [r12 + r8]
    mov r14d, 1                 ; instruction length
    xor r15d, r15d              ; stack effect
    xor ebx, ebx                ; successor kind: normal/jump/cond/terminal
    cmp eax, 1
    je .cfg_const
    cmp eax, 2
    je .cfg_load_local
    cmp eax, 3
    je .cfg_store_local
    cmp eax, 4
    jb .cfg_special
    cmp eax, 9
    jbe .cfg_arithmetic
    cmp eax, 22
    je .cfg_arithmetic
.cfg_special:
    cmp eax, 10
    je .cfg_jump
    cmp eax, 11
    je .cfg_jump_zero
    cmp eax, 12
    je .cfg_import
    cmp eax, 13
    je .cfg_return
    cmp eax, 14
    je .cfg_halt
    cmp eax, 20
    je .cfg_call
    cmp eax, 21
    je .cfg_return_void
    cmp eax, 15
    je .cfg_byte_const
    cmp eax, 16
    je .cfg_byte_load
    cmp eax, 17
    je .cfg_byte_store
    cmp eax, 18
    je .cfg_duplicate
    cmp eax, 19
    je .cfg_drop
    jmp .bad
.cfg_const:
    mov r14d, 5
    mov r15d, 1
    jmp .cfg_effect
.cfg_load_local:
    mov r14d, 2
    mov r15d, 1
    jmp .cfg_effect
.cfg_store_local:
    mov r14d, 2
    mov r15d, -1
    jmp .cfg_effect
.cfg_arithmetic:
    mov r15d, -1
    jmp .cfg_effect
.cfg_jump:
    mov r14d, 3
    mov ebx, 1
    jmp .cfg_effect
.cfg_jump_zero:
    mov r14d, 3
    mov r15d, -1
    mov ebx, 2
    jmp .cfg_effect
.cfg_return:
    mov r15d, -1
    mov ebx, 3
    jmp .cfg_effect
.cfg_halt:
    mov ebx, 3
    jmp .cfg_effect
.cfg_return_void:
    xor r15d, r15d
    mov ebx, 3
    jmp .cfg_effect
.cfg_call:
    mov r14d, 5
    movzx edx, byte [r12 + r8 + 3]
    movzx ecx, byte [r12 + r8 + 4]
    cmp edx, 255
    ja .bad
    cmp ecx, 1
    ja .bad
    mov r15d, ecx
    sub r15d, edx
    mov ebx, 4
    jmp .cfg_effect
.cfg_byte_const:
    movzx edx, byte [r12 + r8 + 1]
    lea r14d, [edx + 2]
    mov r15d, 1
    jmp .cfg_effect
.cfg_byte_load:
    mov r15d, -1
    jmp .cfg_effect
.cfg_byte_store:
    mov r15d, -3
    jmp .cfg_effect
.cfg_duplicate:
    mov r15d, 1
    jmp .cfg_effect
.cfg_drop:
    mov r15d, -1
    jmp .cfg_effect
.cfg_import:
    mov r14d, 3
    movzx edx, byte [r12 + r8 + 1]
    movzx ecx, byte [r12 + r8 + 2]
    cmp edx, 1
    je .cfg_import_pop
    cmp edx, 2
    je .cfg_import_exit
    cmp edx, 3
    je .cfg_import_zero
    cmp edx, 4
    je .cfg_import_pop
    cmp edx, 5
    je .cfg_import_pop
    cmp edx, 6
    je .cfg_import_pop2
    cmp edx, 7
    je .cfg_import_pop2
    cmp edx, 8
    je .cfg_import_zero
    cmp edx, 9
    je .cfg_import_pop
    cmp edx, 10
    je .cfg_import_zero
    cmp edx, 11
    je .cfg_import_zero
    cmp edx, 12
    je .cfg_import_zero
    cmp edx, 13
    je .cfg_import_pop2
    cmp edx, 14
    je .cfg_import_one_result
    jmp .bad
.cfg_import_pop:
    mov r15d, -1
    jmp .cfg_effect
.cfg_import_pop2:
    mov r15d, -2
    jmp .cfg_effect
.cfg_import_zero:
    xor r15d, r15d
    jmp .cfg_effect
.cfg_import_one_result:
    mov r15d, 1
    jmp .cfg_effect
.cfg_import_exit:
    mov r15d, -1
    mov ebx, 3
.cfg_effect:
    mov edx, r9d
    add edx, r15d
    js .bad
    cmp edx, 192
    ja .bad
    mov r9d, edx                ; output depth
    ; Merge the fall-through successor for normal and conditional ops.
    cmp ebx, 1
    je .cfg_target
    cmp ebx, 3
    je .cfg_target
    mov edx, r8d
    add edx, r14d
    jc .bad
    cmp edx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rdx], 1
    jne .bad
    movzx ecx, byte [gwo2_depths + rdx]
    cmp ecx, 0xff
    jne .cfg_fall_known
    mov [gwo2_depths + rdx], r9b
    mov r10d, 1
    jmp .cfg_target
.cfg_fall_known:
    cmp ecx, r9d
    jne .bad
.cfg_target:
    ; Unconditional and conditional jumps merge their encoded target.
    cmp ebx, 0
    je .cfg_next
    cmp ebx, 3
    je .cfg_next
    cmp ebx, 4
    je .cfg_call_target
    movsx edx, word [r12 + r8 + 1]
    lea ecx, [r8 + r14]
    add ecx, edx
    js .bad
    cmp ecx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rcx], 1
    jne .bad
    movzx edx, byte [gwo2_depths + rcx]
    cmp edx, 0xff
    jne .cfg_target_known
    mov [gwo2_depths + rcx], r9b
    mov r10d, 1
    jmp .cfg_next
.cfg_target_known:
    cmp edx, r9d
    jne .bad
.cfg_call_target:
    movzx ecx, word [r12 + r8 + 1]
    cmp ecx, r13d
    jae .bad
    cmp byte [gwo2_boundaries + rcx], 1
    jne .bad
    movzx edx, byte [r12 + r8 + 3]
    movzx eax, byte [gwo2_depths + rcx]
    cmp eax, 0xff
    jne .cfg_call_known
    mov [gwo2_depths + rcx], dl
    mov r10d, 1
    jmp .cfg_next
.cfg_call_known:
    cmp eax, edx
    jne .bad
.cfg_next:
    inc r8d
    jmp .cfg_scan
.cfg_done_scan:
    test r10d, r10d
    jnz .cfg_pass
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
    cmp eax, 3                  ; file_open
    je .file_open
    cmp eax, 4                  ; file_read
    je .file_read
    cmp eax, 5                  ; file_write
    je .file_write
    cmp eax, 6                  ; file_close
    je .file_close
    cmp eax, 7                  ; file_stat
    je .file_stat
    cmp eax, 0x0d               ; path_create
    je .path_create
    cmp eax, 0x0e               ; file_unlink
    je .file_unlink
    cmp eax, 0x0f               ; process_spawn(image, size)
    je .process_spawn
    cmp eax, 0x10               ; process_wait(pid)
    je .process_wait
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
    mov rax, [r12 + PROC_CONTEXT]
    jmp process_iret_context
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
    mov byte [abs gfs_active_super], 0
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
    mov byte [abs gfs_active_super], 1
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

; -------------------------- GFS2 kernel file path -------------------------
; The first kernel-visible file profile is deliberately bounded to one root
; directory and one 512-byte extent per regular file.  The on-disk metadata,
; checksums, allocation bitmap, inactive-superblock commit, and ATA writes are
; nevertheless real GFS2 operations; the bound is an explicit Alpha limit,
; not a fake success path.
gfs_copy_user_path:
    ; RDI=NUL-terminated user path.  Copy <=31 bytes after validating each
    ; byte through the same page-walk used by console_write.
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, gfs_path_buffer
    xor r14d, r14d
.next:
    cmp r14d, 31
    jae .bad
    mov rdi, r12
    mov esi, 1
    call user_span_valid
    test eax, eax
    jz .bad
    mov al, [r12]
    mov [r13], al
    inc r12
    inc r13
    inc r14d
    test al, al
    jnz .next
    mov eax, 1
    pop r14
    pop r13
    pop r12
    ret
.bad:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    ret

gfs_read_inode:
    ; RDI=inode number.  RAX returns a validated pointer into the shared
    ; gfs_inode_block buffer, or zero for an empty/corrupt inode.
    cmp rdi, 1
    jb .bad
    cmp rdi, 32
    ja .bad
    dec edi
    mov r9d, edi
    shr edi, 2
    add edi, 3
    mov rsi, gfs_inode_block
    call ata_block_read
    test eax, eax
    jz .bad
    mov rax, gfs_inode_block
    and r9d, 3
    shl r9, 7
    add rax, r9
    cmp dword [rax], 0x324f4e49 ; INO2
    jne .bad
    push rax
    mov rdi, rax
    mov esi, 120
    call gwo_fnv32
    pop rdi
    cmp eax, [rdi + 120]
    jne .bad
    cmp dword [rdi + 16], 8
    ja .bad
    cmp qword [rdi + 8], 0x200000
    ja .bad
    mov rax, rdi
    ret
.bad:
    xor eax, eax
    ret

gfs_dir_read:
    mov edi, 11
    mov rsi, gfs_dir_buffer
    jmp ata_block_read

gfs_dir_lookup:
    ; gfs_path_buffer is a validated NUL-terminated name.  RAX returns the
    ; inode number, or zero; EDX returns the directory slot or 0xff.
    call gfs_dir_read
    test eax, eax
    jz .bad
    xor r8d, r8d
    mov r11d, 0xff
.entry:
    cmp r8d, 8
    jae .missing
    mov r9, r8
    shl r9, 6
    add r9, gfs_dir_buffer
    movzx ecx, byte [r9]
    test ecx, ecx
    jnz .entry_nonempty
    cmp r11d, 0xff
    jne .next
    mov r11d, r8d
    jmp .next
.entry_nonempty:
    cmp ecx, 31
    ja .next
    push r8
    push r9
    mov rdi, r9
    mov esi, 60
    call gwo_fnv32
    pop r9
    pop r8
    cmp eax, [r9 + 60]
    jne .next
    xor edx, edx
.compare:
    cmp edx, ecx
    jae .name_done
    mov al, [r9 + 6 + rdx]
    cmp al, [gfs_path_buffer + rdx]
    jne .next
    inc edx
    jmp .compare
.name_done:
    cmp byte [gfs_path_buffer + rdx], 0
    jne .next
    mov eax, [r9 + 2]
    mov edx, r8d
    ret
.next:
    inc r8d
    jmp .entry
.missing:
    xor eax, eax
    mov edx, r11d
    ret
.bad:
    xor eax, eax
    mov edx, 0xff
    ret

gfs_inode_block_for:
    ; RDI=inode number -> EAX=relative inode block, RDX=byte offset.
    dec edi
    mov eax, edi
    shr eax, 2
    add eax, 3
    and edi, 3
    shl edi, 7
    mov edx, edi
    ret

gfs_commit_super:
    ; Commit the already-updated metadata through the inactive superblock.
    mov rdi, gfs_super_buffer
    mov rax, [rdi + 8]
    inc rax
    mov [rdi + 8], rax
    mov esi, 52
    call gwo_fnv32
    mov [abs gfs_super_buffer + 52], eax
    movzx edi, byte [abs gfs_active_super]
    xor edi, 1
    mov rsi, gfs_super_buffer
    call ata_block_write
    test eax, eax
    jz .bad
    movzx eax, byte [abs gfs_active_super]
    xor eax, 1
    mov [abs gfs_active_super], al
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

gfs_inode_encode_empty:
    ; RDI=inode number, RSI=type (regular file=1).  Creates an empty INO2
    ; record in its table block; callers commit the block afterward.
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov rdi, r12
    call gfs_inode_block_for
    mov r14d, eax
    mov r15d, edx
    mov edi, r14d
    mov rsi, gfs_inode_block
    call ata_block_read
    test eax, eax
    jz .bad
    lea rdi, [gfs_inode_block + r15]
    xor eax, eax
    mov ecx, 16
    rep stosq
    mov dword [gfs_inode_block + r15], 0x324f4e49
    mov word [gfs_inode_block + r15 + 4], r13w
    mov word [gfs_inode_block + r15 + 6], 0644
    mov dword [gfs_inode_block + r15 + 16], 0
    mov rdi, gfs_inode_block
    add rdi, r15
    mov esi, 120
    call gwo_fnv32
    mov [gfs_inode_block + r15 + 120], eax
    mov edi, r14d
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .bad
    mov eax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.bad:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    ret

gfs_create_path:
    ; gfs_path_buffer is populated.  Return inode number or a negative errno.
    call gfs_dir_lookup
    test eax, eax
    jnz .exists
    mov r12d, edx
    cmp r12d, 8
    jae .no_space
    xor r13d, r13d
    mov r14d, 2
.find_inode:
    cmp r14d, 32
    ja .no_space
    mov edi, r14d
    call gfs_read_inode
    test rax, rax
    jz .inode_found
    inc r14d
    jmp .find_inode
.inode_found:
    mov edi, r14d
    mov esi, 1
    call gfs_inode_encode_empty
    test eax, eax
    jnz .inode_ok
    mov al, 'i'
    out 0xe9, al
    jmp .io
.inode_ok:
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jnz .bitmap_ok
    mov al, 'b'
    out 0xe9, al
    jmp .io
.bitmap_ok:
    ; Directory record: name length, flags, inode, name, checksum.
    mov rdi, gfs_dir_buffer
    add rdi, r12
    imul r12, 64
    mov rdi, gfs_dir_buffer
    add rdi, r12
    xor eax, eax
    mov ecx, 8
    rep stosq
    mov rdi, gfs_path_buffer
    xor ecx, ecx
.path_len:
    cmp ecx, 31
    jae .io
    cmp byte [rdi + rcx], 0
    je .path_len_done
    inc ecx
    jmp .path_len
.path_len_done:
    mov rdi, gfs_dir_buffer
    add rdi, r12
    mov [rdi], cl
    mov byte [rdi + 1], 0
    mov dword [rdi + 2], r14d
    mov rsi, gfs_path_buffer
    lea rdi, [rdi + 6]
    mov edx, ecx
    rep movsb
    mov rdi, gfs_dir_buffer
    add rdi, r12
    mov esi, 60
    call gwo_fnv32
    mov [gfs_dir_buffer + r12 + 60], eax
    mov edi, 11
    mov rsi, gfs_dir_buffer
    call ata_block_write
    test eax, eax
    jnz .dir_ok
    mov al, 'd'
    out 0xe9, al
    jmp .io
.dir_ok:
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
.bitmap_write_ok:
    call gfs_commit_super
    test eax, eax
    jz .io
.commit_ok:
    mov eax, r14d
    ret
.exists:
    mov eax, -17
    ret
.no_space:
    mov eax, -28
    ret
.io:
    mov eax, -5
    ret

gfs_file_read_user:
    ; RDI=handle, RSI=user buffer, RDX=count.  Reads are sequential and may
    ; cross the bounded contiguous extent in 512-byte ATA chunks.
    cmp rdi, 1
    jne .bad_handle
    mov r12, [abs current_process]
    mov r13, rsi
    mov r14, rdx
    test r14, r14
    jz .zero
    cmp r14, GFS_MAX_FILE_BYTES
    ja .invalid
    mov rax, [r12 + PROC_OFFSET]
    mov r15, rax
    mov rdi, [r12 + PROC_INODE]
    call gfs_read_inode
    test rax, rax
    jnz .inode_read_ok
    jmp .io
.inode_read_ok:
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov r8, [rbx + 8]
    cmp r15, r8
    jae .zero
    sub r8, r15
    cmp r14, r8
    jbe .count_ready
    mov r14, r8
.count_ready:
    test r14, r14
    jz .zero
    cmp dword [rbx + 16], 1
    jne .io
    mov rdi, r13
    mov rsi, r14
    call user_span_valid
    test eax, eax
    jz .fault
    xor r11d, r11d
.read_block:
    cmp r11d, r14d
    jae .read_done
    mov rax, r15
    add rax, r11
    mov rcx, rax
    shr rax, 9
    cmp rax, [rbx + 32]
    jae .io
    add rax, [rbx + 24]
    mov rdi, rax
    mov rsi, gfs_data_buffer
    call ata_block_read
    test eax, eax
    jz .io
    mov rax, r15
    add rax, r11
    mov edx, eax
    and edx, 511
    mov ecx, 512
    sub ecx, edx
    mov eax, r14d
    sub eax, r11d
    cmp eax, ecx
    jae .read_chunk_ready
    mov ecx, eax
.read_chunk_ready:
    mov r8d, ecx
    mov rsi, gfs_data_buffer
    add rsi, rdx
    mov rdi, r13
    add rdi, r11
    rep movsb
    add r11d, r8d
    jmp .read_block
.read_done:
    add [r12 + PROC_OFFSET], r14
    mov rax, r14
    ret
.zero:
    xor eax, eax
    ret
.bad_handle:
    mov eax, -9
    ret
.invalid:
    mov eax, -22
    ret
.fault:
    mov eax, -14
    ret
.io:
    mov eax, -5
    ret

gfs_file_write_user:
    ; RDI=handle, RSI=user bytes, RDX=count.  Replace the file with one
    ; contiguous extent of bounded ATA blocks.  User bytes are copied and
    ; flushed a block at a time before the inode/bitmap/superblock commit.
    cmp rdi, 1
    jne .bad_handle
    mov r12, [abs current_process]
    mov r13, rsi
    mov r14, rdx
    cmp r14, GFS_MAX_FILE_BYTES
    ja .invalid
    cmp qword [r12 + PROC_OFFSET], 0
    jne .invalid
    test r14, r14
    jz .zero
    mov rdi, r13
    mov rsi, r14
    call user_span_valid
    test eax, eax
    jz .fault
    mov edi, [r12 + PROC_INODE]
    call gfs_read_inode
    test rax, rax
    jz .io
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jz .io
    ; Release every block in the previous extent.
    cmp dword [rbx + 16], 1
    jne .allocate
    mov r10d, [rbx + 32]
    mov r11d, [rbx + 24]
.release_block:
    test r10d, r10d
    jz .allocate
    mov eax, r11d
    mov edx, eax
    shr edx, 3
    mov r9d, edx
    movzx r8d, byte [gfs_bitmap_buffer + r9]
    mov edx, eax
    and edx, 7
    mov ecx, edx
    mov eax, 1
    shl eax, cl
    not al
    and r8b, al
    mov [gfs_bitmap_buffer + r9], r8b
    inc r11d
    dec r10d
    jmp .release_block
.allocate:
    mov eax, r14d
    add eax, 511
    shr eax, 9
    mov [abs gfs_io_blocks], eax
    test eax, eax
    jz .zero
    mov r15d, 12
.find_extent:
    cmp r15d, [abs gfs_total_blocks]
    jae .no_space
    xor r8d, r8d
.check_extent:
    cmp r8d, [abs gfs_io_blocks]
    jae .extent_found
    mov eax, r15d
    add eax, r8d
    mov ecx, eax
    shr ecx, 3
    movzx edx, byte [gfs_bitmap_buffer + rcx]
    mov ecx, eax
    and ecx, 7
    bt edx, ecx
    jc .next_extent
    inc r8d
    jmp .check_extent
.next_extent:
    inc r15d
    jmp .find_extent
.extent_found:
    mov [abs gfs_io_start], r15d
    xor r10d, r10d
.mark_extent:
    cmp r10d, [abs gfs_io_blocks]
    jae .write_extent
    mov eax, r15d
    add eax, r10d
    mov ecx, eax
    shr ecx, 3
    mov r9d, ecx
    mov edx, eax
    and edx, 7
    mov ecx, edx
    mov eax, 1
    shl eax, cl
    or byte [gfs_bitmap_buffer + r9], al
    inc r10d
    jmp .mark_extent
.write_extent:
    xor r15d, r15d
.write_block:
    cmp r15d, [abs gfs_io_blocks]
    jae .update_inode
    mov eax, r15d
    shl eax, 9
    mov edx, r14d
    sub edx, eax
    cmp edx, 512
    jbe .write_chunk_ready
    mov edx, 512
.write_chunk_ready:
    mov rdi, gfs_data_buffer
    xor eax, eax
    mov ecx, 64
    rep stosq
    mov rsi, r13
    mov eax, r15d
    shl eax, 9
    add rsi, rax
    mov ecx, edx
    mov rdi, gfs_data_buffer
    rep movsb
    mov eax, [abs gfs_io_start]
    add eax, r15d
    mov edi, eax
    mov rsi, gfs_data_buffer
    call ata_block_write
    test eax, eax
    jz .io
    inc r15d
    jmp .write_block
.update_inode:
    mov [rbx + 8], r14
    test r14, r14
    jz .empty_extent
    mov dword [rbx + 16], 1
    mov eax, [abs gfs_io_start]
    mov [rbx + 24], eax
    mov eax, [abs gfs_io_blocks]
    mov [rbx + 32], eax
    jmp .inode_checksum
.empty_extent:
    mov dword [rbx + 16], 0
    mov qword [rbx + 24], 0
    mov dword [rbx + 32], 0
.inode_checksum:
    mov rdi, rbx
    mov esi, 120
    call gwo_fnv32
    mov [rbx + 120], eax
    mov rdi, [r12 + PROC_INODE]
    call gfs_inode_block_for
    mov edi, eax
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
    call gfs_commit_super
    test eax, eax
    jz .io
    mov [r12 + PROC_FILE_SIZE], r14
    mov [r12 + PROC_OFFSET], r14
    mov rax, r14
    ret
.zero:
    ; Zero-length replacement still performs the inode/bitmap transaction by
    ; recursing through the same path with a zeroed data buffer.
    jmp .invalid
.bad_handle:
    mov eax, -9
    ret
.invalid:
    mov eax, -22
    ret
.fault:
    mov eax, -14
    ret
.no_space:
    mov eax, -28
    ret
.io:
    mov eax, -5
    ret

gfs_replace_file_kernel:
    ; RDI=inode, RSI=kernel source, RDX=size.  Shared metadata transaction for
    ; the recovery shell and the syscall path; caller has already performed any
    ; user-range validation required by its ABI.
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    cmp r14, 512
    ja .invalid
    mov rdi, r12
    call gfs_read_inode
    test rax, rax
    jz .io
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jz .io
    cmp dword [rbx + 16], 1
    jne .allocate
    mov edx, [rbx + 24]
    mov ecx, edx
    shr ecx, 3
    mov r8d, ecx
    movzx eax, byte [gfs_bitmap_buffer + rcx]
    mov ecx, edx
    and ecx, 7
    mov edx, 1
    shl edx, cl
    not dl
    and al, dl
    mov [gfs_bitmap_buffer + r8], al
.allocate:
    xor r15d, r15d
    test r14, r14
    jz .update
    mov r15d, 12
.find:
    cmp r15d, [abs gfs_total_blocks]
    jae .no_space
    mov eax, r15d
    mov ecx, eax
    shr ecx, 3
    movzx edx, byte [gfs_bitmap_buffer + rcx]
    mov ecx, r15d
    and ecx, 7
    bt edx, ecx
    jc .next
    mov eax, 1
    shl eax, cl
    mov ecx, r15d
    shr ecx, 3
    or byte [gfs_bitmap_buffer + rcx], al
    mov rdi, gfs_data_buffer
    mov rsi, r13
    mov rcx, r14
    rep movsb
    mov edi, r15d
    mov rsi, gfs_data_buffer
    call ata_block_write
    test eax, eax
    jz .io
    jmp .update
.next:
    inc r15d
    jmp .find
.update:
    mov [rbx + 8], r14
    test r14, r14
    jz .empty
    mov dword [rbx + 16], 1
    mov [rbx + 24], r15
    mov dword [rbx + 32], 1
    jmp .checksum
.empty:
    mov dword [rbx + 16], 0
    mov qword [rbx + 24], 0
    mov dword [rbx + 32], 0
.checksum:
    mov rdi, rbx
    mov esi, 120
    call gwo_fnv32
    mov [rbx + 120], eax
    mov rdi, r12
    call gfs_inode_block_for
    mov edi, eax
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
    call gfs_commit_super
    test eax, eax
    jz .io
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.invalid:
    mov eax, -22
    jmp .return
.no_space:
    mov eax, -28
    jmp .return
.io:
    mov eax, -5
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

gfs_shell_name_copy:
    mov rsi, gfs_shell_name
    mov rdi, gfs_path_buffer
    mov ecx, gfs_shell_name_end - gfs_shell_name
    rep movsb
    ret

gfs_shell_save:
    call gfs_shell_name_copy
    call gfs_dir_lookup
    test eax, eax
    jnz .have_inode
    call gfs_create_path
    test eax, eax
    js .fail
.have_inode:
    mov edi, eax
    mov rsi, gfs_shell_source
    mov edx, gfs_shell_source_end - gfs_shell_source
    call gfs_replace_file_kernel
    test eax, eax
    js .fail
    mov rsi, shell_save_ok
    call console_write_string
    ret
.fail:
    mov rsi, shell_unknown
    call console_write_string
    ret

gfs_shell_ls:
    call gfs_dir_read
    test eax, eax
    jz .fail
    xor r12d, r12d
.entry:
    cmp r12d, 8
    jae .done
    mov r9, r12
    shl r9, 6
    add r9, gfs_dir_buffer
    movzx ecx, byte [r9]
    test ecx, ecx
    jz .next
    cmp ecx, 31
    ja .next
    mov rsi, r9
    mov rdi, r9
    mov esi, 60
    call gwo_fnv32
    cmp eax, [r9 + 60]
    jne .next
    movzx ecx, byte [r9]
    lea rsi, [r9 + 6]
    call console_write_bytes
    mov rsi, shell_line_end
    call console_write_string
.next:
    inc r12d
    jmp .entry
.done:
    ret
.fail:
    mov rsi, shell_unknown
    call console_write_string
    ret

gfs_shell_cat:
    call gfs_shell_name_copy
    call gfs_dir_lookup
    test eax, eax
    jz .fail
    mov edi, eax
    call gfs_read_inode
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .fail
    cmp qword [rbx + 8], 512
    ja .fail
    cmp dword [rbx + 16], 1
    jne .empty
    mov rdi, [rbx + 24]
    mov rsi, gfs_data_buffer
    call ata_block_read
    test eax, eax
    jz .fail
    mov ecx, [rbx + 8]
    mov rsi, gfs_data_buffer
    call console_write_bytes
.empty:
    mov rsi, shell_line_end
    call console_write_string
    ret
.fail:
    mov rsi, shell_unknown
    call console_write_string
    ret
.invalid:
    mov eax, -22
    jmp .return
.no_space:
    mov eax, -28
    jmp .return
.io:
    mov eax, -5
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

gfs_file_open_user:
    ; RDI=user path, RSI=reserved flags.  The first handle table is one entry
    ; per process; all handle state is stored in the owned process object.
    mov r12, [abs current_process]
    cmp dword [r12 + PROC_HANDLE], 0
    jne .busy
    call gfs_copy_user_path
    test eax, eax
    jz .fault
    call gfs_dir_lookup
    test eax, eax
    jz .missing
    mov r13d, eax
    mov edi, eax
    call gfs_read_inode
    test rax, rax
    jz .io
    cmp word [rax + 4], 1
    jne .io
    mov dword [r12 + PROC_HANDLE], 1
    mov dword [r12 + PROC_INODE], r13d
    mov qword [r12 + PROC_OFFSET], 0
    mov rax, [rax + 8]
    mov [r12 + PROC_FILE_SIZE], rax
    mov eax, 1
    ret
.busy:
    mov eax, -16
    ret
.missing:
    mov eax, -2
    ret
.fault:
    mov eax, -14
    ret
.io:
    mov eax, -5
    ret

gfs_file_close_user:
    cmp rdi, 1
    jne .bad
    mov r12, [abs current_process]
    mov dword [r12 + PROC_HANDLE], 0
    mov qword [r12 + PROC_OFFSET], 0
    mov qword [r12 + PROC_INODE], 0
    mov eax, 0
    ret
.bad:
    mov eax, -9
    ret

gfs_file_stat_user:
    ; RDI=handle, RSI=user stat buffer (size u64, mode u32, reserved u32).
    cmp rdi, 1
    jne .bad
    mov r12, [abs current_process]
    mov rdi, rsi
    mov esi, 16
    call user_span_valid
    test eax, eax
    jz .fault
    mov edi, [r12 + PROC_INODE]
    call gfs_read_inode
    test rax, rax
    jz .io
    mov r13, rax
    mov rdi, rsi
    mov rax, [r13 + 8]
    mov [rdi], rax
    movzx eax, word [r13 + 6]
    mov [rdi + 8], eax
    mov dword [rdi + 12], 0
    xor eax, eax
    ret
.bad:
    mov eax, -9
    ret
.fault:
    mov eax, -14
    ret
.io:
    mov eax, -5
    ret

gfs_path_create_user:
    ; RDI=user path.  Create a regular empty INO2 record and return its handle.
    mov r12, [abs current_process]
    cmp dword [r12 + PROC_HANDLE], 0
    jne .busy
    call gfs_copy_user_path
    test eax, eax
    jz .fault
    call gfs_create_path
    ; gfs_create_path uses r12-r14 for its directory/inode transaction.
    ; Reload the process object before publishing the new handle state.
    mov r12, [abs current_process]
    test eax, eax
    js .return_error
    mov r13d, eax
    mov dword [r12 + PROC_HANDLE], 1
    mov dword [r12 + PROC_INODE], r13d
    mov qword [r12 + PROC_OFFSET], 0
    mov qword [r12 + PROC_FILE_SIZE], 0
    mov eax, 1
    ret
.return_error:
    ret
.busy:
    mov eax, -16
    ret
.fault:
    mov eax, -14
    ret

gfs_file_unlink_user:
    ; RDI=user path.  Alpha v1 unlinks one regular root entry with the same
    ; checked inode/bitmap/directory/superblock transaction as the host tool.
    mov r12, [abs current_process]
    cmp dword [r12 + PROC_HANDLE], 0
    jne .busy
    call gfs_copy_user_path
    test eax, eax
    jz .fault
    call gfs_dir_lookup
    test eax, eax
    jz .missing
    mov r13d, eax
    mov r14d, edx
    cmp r13d, 1
    je .protected
    mov edi, r13d
    call gfs_read_inode
    test rax, rax
    jz .io
    mov rbx, rax
    cmp word [rbx + 4], 1
    jne .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_read
    test eax, eax
    jz .io
    cmp dword [rbx + 16], 1
    jne .clear_inode
    mov rdx, [rbx + 24]
    cmp rdx, 12
    jb .io
    mov r10d, [rbx + 32]
    mov eax, edx
    add eax, r10d
    cmp eax, [abs gfs_total_blocks]
    jae .io
    mov r11d, edx
.unlink_extent_block:
    test r10d, r10d
    jz .clear_inode
    mov eax, r11d
    mov edx, eax
    shr edx, 3
    mov r8d, edx
    movzx r9d, byte [gfs_bitmap_buffer + r8]
    mov edx, eax
    and edx, 7
    mov eax, 1
    mov ecx, edx
    shl eax, cl
    not al
    and r9b, al
    mov [gfs_bitmap_buffer + r8], r9b
    inc r11d
    dec r10d
    jmp .unlink_extent_block
.clear_inode:
    mov edi, r13d
    call gfs_inode_block_for
    mov r8d, eax
    mov r9d, edx
    lea rdi, [gfs_inode_block + r9]
    xor eax, eax
    mov ecx, 16
    rep stosq
    mov edi, r8d
    mov rsi, gfs_inode_block
    call ata_block_write
    test eax, eax
    jz .io
    imul r14, 64
    lea rdi, [gfs_dir_buffer + r14]
    xor eax, eax
    mov ecx, 8
    rep stosq
    mov edi, 11
    mov rsi, gfs_dir_buffer
    call ata_block_write
    test eax, eax
    jz .io
    mov edi, 2
    mov rsi, gfs_bitmap_buffer
    call ata_block_write
    test eax, eax
    jz .io
    call gfs_commit_super
    test eax, eax
    jz .io
    xor eax, eax
    ret
.busy:
    mov eax, -16
    ret
.fault:
    mov eax, -14
    ret
.missing:
    mov eax, -2
    ret
.protected:
    mov eax, -13
    ret
.io:
    mov eax, -5
    ret

shell_start:
    mov rsi, shell_banner
    call console_write_string
    mov rsi, shell_prompt
    call console_write_string
    ret

console_input_push:
    ; AL=one keyboard byte.  Drop the newest byte only when the bounded ring
    ; is full; the emergency shell and ring-3 console reader share this queue.
    push rbx
    push rdx
    mov dl, [abs console_input_tail]
    mov bl, dl
    inc bl
    cmp bl, [abs console_input_head]
    je .done
    movzx edx, dl
    mov [abs console_input_buffer + rdx], al
    inc dl
    mov [abs console_input_tail], dl
.done:
    pop rdx
    pop rbx
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
    cmp ebx, 0x2d
    je .x
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
.x:
    mov al, 'x'
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
    call console_input_push
    call console_write_char
.done:
    ret
.backspace:
    cmp byte [abs shell_len], 0
    je .done
    dec byte [abs shell_len]
    mov dl, [abs console_input_tail]
    cmp dl, [abs console_input_head]
    je .visual_backspace
    dec dl
    mov [abs console_input_tail], dl
.visual_backspace:
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
    call console_input_push
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
    mov rdi, cmd_save
    mov ecx, 4
    call shell_match
    test al, al
    jnz .save
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
    call gfs_shell_ls
    ret
.cat:
    call gfs_shell_cat
    ret
.mem:
    mov rsi, shell_mem
    call console_write_string
    ret
.tasks:
    mov rsi, shell_tasks
    call console_write_string
    ret
.save:
    call gfs_shell_save
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
    add r12, [abs VM_ENTRY_SLOT]
    xor eax, eax
    mov rdi, VM_STACK_BASE
    mov ecx, 128
    rep stosq
    mov qword [abs VM_CONST_CURSOR], VM_CONST_BASE
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
    cmp eax, 255
    jae .fail
    cmp r13, 128
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
    mov r8, [abs VM_CONST_CURSOR]
    mov r9, r8
    add r9, rax
    inc r9
    cmp r9, VM_CONST_LIMIT
    ja .fail
    cmp r13, 128
    jae .fail
    mov rdi, r8
    mov rsi, r12
    mov rcx, rax
    rep movsb
    mov byte [r8 + rax], 0
    mov [abs VM_CONST_CURSOR], r9
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
    cmp r13, 128
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
    cmp eax, 1
    je .import_print
    cmp eax, 2
    je .import_exit
    cmp eax, 3
    je .import_newline
    cmp eax, 4
    je .import_console_read
    cmp eax, 5
    je .import_file_open
    cmp eax, 6
    je .import_file_read
    cmp eax, 7
    je .import_file_write
    cmp eax, 8
    je .import_file_close
    cmp eax, 9
    je .import_file_stat
    cmp eax, 10
    je .import_mem_grow
    cmp eax, 11
    je .import_path_create
    cmp eax, 12
    je .import_file_unlink
    cmp eax, 13
    je .import_print_bytes
    cmp eax, 14
    je .import_task_yield
    cmp eax, 15
    je .import_process_spawn
    cmp eax, 16
    je .import_process_wait
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
    mov eax, 1
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 3
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 4
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 5
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 6
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 7
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 8
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 0x0d
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 0x0e
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 2
    syscall
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    jmp .loop
.import_task_yield:
    test ebx, ebx
    jnz .fail
    mov [abs VM_PC_SLOT], r12
    mov [abs VM_SP_SLOT], r13
    mov [abs VM_STEP_SLOT], r14
    mov eax, 0x0c
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
    mov [abs VM_STACK_BASE + r13 * 8], rax
    inc r13
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
    mov eax, 0x0f
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
    mov eax, 0x10
    syscall
    movsxd rax, eax
    mov r12, [abs VM_PC_SLOT]
    mov r13, [abs VM_SP_SLOT]
    mov r14, [abs VM_STEP_SLOT]
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
user_payload_entry:
    dd 0
align 8
gwo2_boundaries:
    times MAX_PAYLOAD_BYTES db 0
gwo2_depths:
    times MAX_PAYLOAD_BYTES db 0
ata_ready:
    db 0
gfs_mount_valid:
    db 0
align 8
ata_capacity:
    dq 0
gfs_total_blocks:
    dq 0
gfs_active_super:
    db 0
align 8
gfs_bitmap_buffer:
    times 512 db 0
gfs_inode_block:
    times 512 db 0
gfs_dir_buffer:
    times 512 db 0
gfs_data_buffer:
    times 512 db 0
gfs_path_buffer:
    times 32 db 0
align 8
gfs_io_user:
    dq 0
gfs_io_size:
    dq 0
gfs_io_start:
    dd 0
gfs_io_blocks:
    dd 0
align 512
ata_identify_buffer:
    times 512 db 0
gfs_super_buffer:
    times 512 db 0
gfs_recovery_buffer:
    times 512 db 0
align 4096
user_payload_kernel:
    times MAX_GWO_IMAGE_BYTES db 0
align 4096
user_gwo_staging:
    times MAX_GWO_IMAGE_BYTES db 0
shell_len:
    db 0
shell_done:
    db 0
vga_cursor:
    dq 0
shell_buffer:
    times 64 db 0
console_input_head:
    db 0
console_input_tail:
    db 0
align 16
console_input_buffer:
    times 256 db 0
shell_banner:
    db 13, 10, 'GrOS x86_64', 13, 10, 0
shell_prompt:
    db 'Grogan> ', 0
shell_help:
    db 'help ls cat save mem tasks reboot', 13, 10, 0
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
shell_save_ok:
    db 'SAVE OK', 13, 10, 0
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
cmd_save:
    db 'save', 0
cmd_reboot:
    db 'reboot', 0
gfs_shell_name:
    db 'hello.grw', 0
gfs_shell_name_end:
gfs_shell_source:
    db 'target "gros.x86.bios.longmode.grogan.v1"', 10
    db 'fn main() -> void {', 10
    db '    print_i32(28);', 10
    db '}', 10
gfs_shell_source_end:
align 16
user_gwo_image:
    incbin "build/generated/grogan-user.gwo"
user_gwo_image_end:
align 16
user_helper_image:
    incbin "build/generated/grogan-helper.gwo"
user_helper_image_end:
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
