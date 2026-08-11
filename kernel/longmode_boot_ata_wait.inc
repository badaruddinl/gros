ata_wait_drq:
    ; Poll BSY/ERR/DRQ with a finite budget.  A device error or timeout is a
    ; normal block-layer failure, never an infinite interrupt-disabled loop.
%if ATA_TEST_FAULT == 1
    jmp .fail
%elif ATA_TEST_FAULT == 2
    mov ecx, 0x100000
.forced_timeout:
    dec ecx
    jnz .forced_timeout
    jmp .fail
%endif
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
