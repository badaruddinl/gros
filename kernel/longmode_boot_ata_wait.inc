ata_wait_drq:
    ; Poll BSY/ERR/DRQ with a finite budget.  A device error or timeout is a
    ; normal block-layer failure, never an infinite interrupt-disabled loop.
    mov byte [abs ata_failure_code], 0
%if ATA_TEST_FAULT == 1
    ; Exercise the real ERR branch with a deterministic status byte.  This is
    ; intentionally a status-read shim, not a direct jump to the failure
    ; return, so the injected lane covers the same decision as hardware ERR.
    mov al, 1
    jmp .status
%elif ATA_TEST_FAULT == 2
    ; Exercise the finite no-DRQ poll with a deterministic status byte.  The
    ; bounded loop below is the same timeout branch used by a real device.
    mov ecx, 0x100000
.forced_timeout:
    xor eax, eax
    jmp .status
%else
    mov dx, ATA_PRIMARY_STATUS
    mov ecx, 0x100000
.poll:
    in al, dx
%endif
.status:
    test al, 0x80
    jnz .again
    test al, 1
    jnz .err
    test al, 8
    jnz .ready
.again:
    dec ecx
%if ATA_TEST_FAULT == 2
    jnz .forced_timeout
%elif ATA_TEST_FAULT == 1
    jmp .timeout
%else
    jnz .poll
%endif
.timeout:
    mov byte [abs ata_failure_code], 2
    xor eax, eax
    ret
.err:
    mov byte [abs ata_failure_code], 1
    xor eax, eax
    ret
.ready:
    mov eax, 1
    ret
