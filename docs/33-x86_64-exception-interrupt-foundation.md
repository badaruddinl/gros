# x86_64 Exception and Interrupt Foundation

The BIOS long-mode transition image installs a 256-entry x86_64 IDT before it
executes application/kernel work. Every entry is a present, kernel-only
interrupt gate to the same fail-stop exception handler.

The boot proof intentionally executes `UD2`. QEMU must emit `LM64IDTEX06` on
debug port `0xe9`: `LM64IDT` proves long-mode and IDT installation; `EX06`
proves vector 6 reached the installed handler.

The handler halts rather than issuing `iretq`. This is intentional: a complete
exception-frame ABI (including error-code vectors, register saving, nesting,
and recovery) is not yet defined. Failing closed avoids resuming corrupted or
unknown state.

The IDT is static in the image and mapped by the initial 2 MiB identity map.
Hardware IRQ enabling, PIC/APIC configuration, timer interrupts, syscall
entry, task switching, and recoverable fault handling remain later phases.
