# BIOS to x86_64 Long-Mode Transition Seed

This document defines the implemented, deliberately narrow bootstrap transition
seed that backs the `gros.x86.bios.longmode.grogan.v0` product profile. Its
artifact is `gros-longmode.img`, built from `kernel/longmode_boot.asm`. The
profile is the next GrOS boot path alongside the current real16 runtime; it is
not yet a complete kernel or a replacement for every stage-2 compatibility path.

## Contract

The image is a 33-sector raw BIOS disk image:

1. sector 1 loads sectors 2 through 33 to `0000:8000` and transfers control;
2. stage 2 enables A20, obtains the BIOS E820 map, then enters protected mode;
3. it creates PML4, PDPT, and PD tables and identity-maps the first 4 MiB as
   two 2 MiB windows;
4. it enables PAE, EFER.LME, and paging, then jumps to a 64-bit code segment;
5. the x86_64 entry writes `LM64IDTGRO64` to QEMU debug port `0xe9` and enters
   the bounded Grogan bootstrap seed.

The marker is proof of the transition entry only. It is not proof of an
interrupt subsystem, scheduler, allocator, filesystem, process model, or
general x86_64 kernel.

## Bootstrap Information ABI

All addresses below are physical addresses while identity mapping is active.

| Address | Meaning | Owner |
| --- | --- | --- |
| `0000:5ffc` | E820 entry count (`u16`) | stage 2 |
| `0000:5ffe` | BIOS boot drive (`u8`, original `DL`) | stage 1 |
| `0000:6000` | E820 entries, 24 bytes each | BIOS/stage 2 |
| `0000:8000` | loaded transition stage | stage 1 |
| `0000:90000` | temporary protected/long-mode stack top | transition stage |
| `0000:1000..3fff` | PML4, PDPT, and PD pages | transition stage |

The transition fails closed (halts) if disk loading or E820 discovery fails.
No later code may overwrite the boot-info block or page-table pages before it
copies or explicitly retires them.

## Verification

```bash
make grogan-x86_64-image
make grogan-x86_64-image-failures
make grogan-x86_64-qemu
```

The static validator checks image size, boot signature, boot-info stores, E820,
A20, GDT, control-register, EFER, page-map, profile-marker, and direction-flag
instruction signatures. The negative suite proves corrupted size, signature,
and profile-marker inputs are rejected. The QEMU gate proves that the CPU
reaches the 64-bit Grogan profile entry marker and completes the bounded seed.

## Boundary

The transition mechanism remains registered as `x86.bios.longmode.transition.v0`
and backs `gros.x86.bios.longmode.grogan.v0`. The product profile does not yet
define Grown lowering, a `.gwo` executable format, a syscall ABI, UEFI support,
or Grogan kernel completeness.
