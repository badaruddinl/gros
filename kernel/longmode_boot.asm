; GrOS Grogan x86_64 BIOS profile bootstrap.
; The first 16-bit sectors remain the firmware handoff; long_mode is the
; product kernel entry for the bounded x86_64 profile seed.
bits 16
section .boot start=0 vstart=0x7c00
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
    ; Zero PML4, PDPT, and PD at 0x1000..0x3fff.
    xor eax, eax
    mov edi, 0x1000
    mov ecx, 3072
    rep stosd
    mov dword [0x1000], 0x2007 ; user-visible table for the bounded window
    mov dword [0x2000], 0x3007
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
grogan_entry:
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x90000
    cld
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
    ; Extend the identity map with a second 2 MiB PDE and record the mapped
    ; window. The page-table pages remain owned by the bootstrap profile.
    mov dword [abs 0x3008], 0x200087 ; user-accessible bounded 2 MiB window
    mov qword [abs paging_window_end], 0x400000
    mov al, 'P'
    out 0xe9, al
    mov al, 'G'
    out 0xe9, al
    mov al, 'M'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
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
    ; Validate and copy the bounded .gwo payload into the user-accessible
    ; second identity window, then enter it through SYSRET. The user program
    ; keeps IF clear; asynchronous IRQ delivery remains a later TSS gate.
    cli
    call gwo_load_user
    mov rcx, 0x200000
    mov r11, 0x2
    mov rsp, 0x2f0000
    db 0x48, 0x0f, 0x07       ; SYSRETQ

gwo_load_user:
    cmp dword [abs user_gwo_image], 0x314f5747 ; GWO1
    jne .fail
    cmp dword [abs user_gwo_image + 4], 1
    jne .fail
    cmp dword [abs user_gwo_image + 8], 24
    jne .fail
    mov ecx, [abs user_gwo_image + 12]
    cmp ecx, 128
    ja .fail
    test ecx, ecx
    jz .fail
    cmp dword [abs user_gwo_image + 16], 0
    jne .fail
    mov r8d, [abs user_gwo_image + 20]
    xor ebx, ebx
    mov rsi, user_gwo_payload
    mov edx, ecx
.sum:
    test edx, edx
    jz .sum_done
    movzx eax, byte [rsi]
    add ebx, eax
    inc rsi
    dec edx
    jmp .sum
.sum_done:
    cmp ebx, r8d
    jne .fail
    mov ecx, [abs user_gwo_image + 12]
    mov rsi, user_gwo_payload
    mov edi, 0x200000
    rep movsb
    mov al, 'G'
    out 0xe9, al
    mov al, 'W'
    out 0xe9, al
    mov al, 'O'
    out 0xe9, al
    mov al, '1'
    out 0xe9, al
    ret
.fail:
    cli
.halt: hlt
    jmp .halt

syscall_entry:
    ; SYSCALL leaves RCX/R11/RSP as the user return state. Save them before
    ; moving to the kernel bootstrap stack; syscall 1 proves return, syscall 2
    ; exits the bounded user payload into the kernel shell path.
    mov [abs user_saved_rip], rcx
    mov [abs user_saved_flags], r11
    mov [abs user_saved_rsp], rsp
    mov rsp, 0x90000
    cmp eax, 1
    je .write
    cmp eax, 2
    je .exit
    mov al, 'S'
    out 0xe9, al
    mov al, '?'
    out 0xe9, al
    jmp .return_user
.write:
    mov al, 'S'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, '1'
    out 0xe9, al
    mov byte [abs user_syscall_seen], 1
    jmp .return_user
.exit:
    mov al, 'S'
    out 0xe9, al
    mov al, 'C'
    out 0xe9, al
    mov al, '2'
    out 0xe9, al
    mov byte [abs user_done], 1
    mov ax, 0x20                 ; restore the kernel data/stack segment after SYSCALL
    mov ds, ax
    mov es, ax
    mov ss, ax
    jmp after_user_mode
.return_user:
    mov rcx, [abs user_saved_rip]
    mov r11, [abs user_saved_flags]
    mov rsp, [abs user_saved_rsp]
    db 0x48, 0x0f, 0x07       ; SYSRETQ

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
    call scheduler_tick
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
    cmp edi, 64
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
    mov byte [r8 + rcx], 0
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
align 8
phys_first_free:
    dq 0
phys_frame_count:
    dd 0
align 8
frame_pool:
    times 64 dq 0
frame_used:
    times 64 db 0
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
user_gwo_payload equ user_gwo_image + 24
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
times 512*32-($-$$) db 0
