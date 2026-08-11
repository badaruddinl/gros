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
    cmp ebx, 0x20
    je .d
    cmp ebx, 0x12
    je .e
    cmp ebx, 0x21
    je .f
    cmp ebx, 0x22
    je .g
    cmp ebx, 0x23
    je .h
    cmp ebx, 0x17
    je .i
    cmp ebx, 0x24
    je .j
    cmp ebx, 0x25
    je .k
    cmp ebx, 0x26
    je .l
    cmp ebx, 0x32
    je .m
    cmp ebx, 0x31
    je .n
    cmp ebx, 0x18
    je .o
    cmp ebx, 0x19
    je .p
    cmp ebx, 0x10
    je .q
    cmp ebx, 0x13
    je .r
    cmp ebx, 0x1f
    je .s
    cmp ebx, 0x14
    je .t
    cmp ebx, 0x16
    je .u
    cmp ebx, 0x2f
    je .v
    cmp ebx, 0x11
    je .w
    cmp ebx, 0x2d
    je .x
    cmp ebx, 0x15
    je .y
    cmp ebx, 0x2c
    je .z
    cmp ebx, 0x39
    je .space
    cmp ebx, 0x34
    je .dot
    cmp ebx, 0x35
    je .slash
    cmp ebx, 0x0c
    je .minus
    cmp ebx, 0x02
    je .one
    cmp ebx, 0x03
    je .two
    cmp ebx, 0x04
    je .three
    cmp ebx, 0x05
    je .four
    cmp ebx, 0x06
    je .five
    cmp ebx, 0x07
    je .six
    cmp ebx, 0x08
    je .seven
    cmp ebx, 0x09
    je .eight
    cmp ebx, 0x0a
    je .nine
    cmp ebx, 0x0b
    je .zero
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
.d:
    mov al, 'd'
    jmp .print
.e:
    mov al, 'e'
    jmp .print
.f:
    mov al, 'f'
    jmp .print
.g:
    mov al, 'g'
    jmp .print
.h:
    mov al, 'h'
    jmp .print
.i:
    mov al, 'i'
    jmp .print
.j:
    mov al, 'j'
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
.n:
    mov al, 'n'
    jmp .print
.o:
    mov al, 'o'
    jmp .print
.p:
    mov al, 'p'
    jmp .print
.q:
    mov al, 'q'
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
.u:
    mov al, 'u'
    jmp .print
.v:
    mov al, 'v'
    jmp .print
.w:
    mov al, 'w'
    jmp .print
.x:
    mov al, 'x'
    jmp .print
.y:
    mov al, 'y'
    jmp .print
.z: mov al, 'z'
    jmp .print
.space:
    mov al, ' '
    jmp .print
.dot:
    mov al, '.'
    jmp .print
.slash:
    mov al, '/'
    jmp .print
.minus:
    mov al, '-'
    jmp .print
.one:
    mov al, '1'
    jmp .print
.two:
    mov al, '2'
    jmp .print
.three:
    mov al, '3'
    jmp .print
.four:
    mov al, '4'
    jmp .print
.five:
    mov al, '5'
    jmp .print
.six:
    mov al, '6'
    jmp .print
.seven:
    mov al, '7'
    jmp .print
.eight:
    mov al, '8'
    jmp .print
.nine:
    mov al, '9'
    jmp .print
.zero:
    mov al, '0'
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
    ; The user shell consumes the canonical carriage-return byte.  Keep the
    ; line-feed purely visual instead of accidentally queueing it as input.
    mov al, 13
    call console_input_push
    cmp qword [abs current_process], 0
    jne .ring3_input
    call shell_execute
.ring3_input:
.input_done:
    mov byte [abs shell_len], 0
    mov byte [abs shell_buffer], 0
    cmp qword [abs current_process], 0
    jne .done
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
