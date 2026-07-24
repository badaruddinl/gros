# BIOS to x86_64 Long-Mode Transition Seed

This document defines the implemented, deliberately narrow bootstrap transition
seed. Its artifact is `gros-longmode.img`, built from
`kernel/longmode_boot.asm`. It is separate from the current real16 GrOS runtime
profile and does not replace the stage-2 boot chain.

## Contract

The image is a 33-sector raw BIOS disk image:

1. sector 1 loads sectors 2 through 33 to `0000:8000` and transfers control;
2. stage 2 enables A20, obtains the BIOS E820 map, then enters protected mode;
3. it creates PML4, PDPT, and PD tables and identity-maps the first 2 MiB;
4. it enables PAE, EFER.LME, and paging, then jumps to a 64-bit code segment;
5. the x86_64 entry writes `LM64` to QEMU debug port `0xe9` and halts.

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
make longmode-image
make longmode-image-failures
make longmode-qemu
```

The static validator checks image size, boot signature, boot-info stores, E820,
A20, GDT, control-register, EFER, and page-map instruction signatures. The
negative suite proves corrupted size, signature, and A20 signatures are
rejected. The QEMU gate proves that the CPU reaches the 64-bit entry marker.

## Boundary

This is registered as `x86.bios.longmode.transition.v0`, a machine bootstrap
seed rather than a GrOS application/runtime profile. It does not define Grown
lowering, a `.gwo` executable format, a syscall ABI, UEFI support, or Grogan
kernel completeness.
