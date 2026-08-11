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
