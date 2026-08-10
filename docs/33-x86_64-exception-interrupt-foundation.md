# x86_64 Exception and Interrupt Foundation

The Grogan x86_64 profile installs a 256-entry x86_64 IDT before it executes
bootstrap work. All entries are present, kernel-only gates. Vector 6 points to
the explicit invalid-opcode fail-stop handler; vector 32 points to the PIT
timer stub; vector 33 points to the PS/2 keyboard stub; remaining vectors use
the default fail-stop handler.

The profile remaps the legacy PIC to vectors 20h through 2fh, unmasks only the
timer and keyboard lines, programs PIT channel 0, and enables interrupts after
all bootstrap seeds are initialized. QEMU must emit the ordered bootstrap
components `LM64IDTGRO64PGM2PMEMF1F2HEAPT1T2FSOK`, then an `IRQ` marker and
finally `EX06` on debug port `0xe9`. `IRQ` proves a real timer interrupt reached
vector 32 and returned; `EX06` proves vector 6 reached the installed exception
handler. Keyboard input may interleave `IRQ` with the shell transcript, so the
gate checks these components independently.

The no-error-code exception frame is the CPU-pushed `[RIP, CS, RFLAGS]` tuple at
stub entry. The seed preserves the scratch register before reporting and then
halts deliberately; error-code vectors, full register frames, nesting, and
recovery are not yet defined. IRQ stubs preserve the scratch register, send
the PIC EOI, and return with `iretq`.

The IDT, PIC/PIT setup, IRQ stubs, and frame-preservation signatures are checked
by `scripts/check_grogan_interrupts.sh` and its negative self-test. The IDT is
static in the image and mapped by the initial 4 MiB identity map. APIC support,
keyboard event buffering, nested interrupts, syscall entry, task switching,
and recoverable fault handling remain later phases.
