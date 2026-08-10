# Grogan x86_64 BIOS Profile Seed

This document promotes the validated BIOS-to-long-mode bootstrap into the first
GrOS product profile for the future Grogan kernel. It is a bounded profile seed,
not a claim that the complete x86_64 kernel already exists.

## Profile

```txt
gros.x86.bios.longmode.grogan.v0
```

The profile is backed by the reproducible artifact:

```txt
kernel/longmode_boot.asm
build/gros-longmode.img
dist/gros-longmode.img
```

The older machine-transition name remains an implementation compatibility label:

```txt
x86.bios.longmode.transition.v0
```

It describes the transition mechanism. The `gros.*` name describes the product
profile that owns the bounded x86_64 bootstrap entry.

## Entry Contract

The BIOS sector loads sectors 2 through 33 at `0000:8000`. The transition stage:

1. preserves the boot drive at `0000:5ffe`;
2. stores the E820 count at `0000:5ffc` and entries at `0000:6000`;
3. enables A20 and enters protected mode;
4. creates the initial identity map for the first 2 MiB;
5. enters the 64-bit code segment and reaches `grogan_entry`.

At `grogan_entry` the seed establishes:

```txt
CS  = 0x18 (64-bit code)
DS  = 0x20
ES  = 0x20
SS  = 0x20
RSP = 0x90000
IF  = 0 (interrupts remain disabled)
DF  = 0 (cleared before string operations)
```

The profile emits `LM64IDTGRO64` on debug port `0xe9` after the IDT is loaded.
The marker proves the product entry and profile ownership; it does not imply a
complete driver, syscall, scheduler, or userspace ABI.

## Owned Bootstrap State

The seed owns the following bounded state while identity mapping is active:

| State | Meaning |
| --- | --- |
| `0x1000..0x3fff` | initial PML4, PDPT, and PD pages |
| `paging_window_end` | identity-map limit at `0x400000` |
| `0x90000` | temporary kernel bootstrap stack top |
| `phys_first_free`, `frame_pool`, `frame_used` | E820 type-1 pages selected in the mapped `0x100000..0x3fffff` window and their ownership bitmap |
| `heap_base`, `heap_slot_count`, `heap_bitmap` | fixed-size slot heap with validated free/reuse |
| `run_queue` | two-entry task descriptor seed and completion state |
| `fs_image` | read-only boot-resident filesystem seed |
| `user_gwo_image` | compiler-produced, checksum-validated bounded GWO1 payload |
| `syscall_entry` | selectors 1/2 with saved RCX/R11/RSP return state |
| `idt` | 256 present kernel-only gates to fail-stop handler |
| `timer_seen`, `last_scancode` | first timer and latest keyboard IRQ state |

The seed fails closed on disk load, E820 discovery, allocation, filesystem, and
exception-probe errors. It enables only the legacy PIC timer/keyboard lines;
the IRQ stubs preserve one scratch register, acknowledge the PIC, and return
with `iretq`. It does not reclaim firmware memory or expose these structures as
a public kernel ABI.

## Validation

```bash
make grogan-x86_64-image
make grogan-x86_64-image-failures
make grogan-syscalls
make grogan-compiler
make grogan-x86_64-qemu
```

The image checker validates the BIOS handoff, control-register transition, IDT,
profile marker, direction-flag normalization, E820 ownership, heap, task
dispatch, and filesystem signatures. The QEMU gate requires these ordered
components (with IRQ delivery allowed to interleave with shell input):

```txt
LM64IDTGRO64PGM2PMEMF1F2HEAPT1T2FSOKSCFGGWO1SC1SC2USEROK ... IRQ ... EX06
```

## Boundary

This profile remains deliberately bounded. It does not yet provide a driver
model, an allocator beyond the bounded frame pool and slot heap, a general
scheduler beyond the two contexts, a writable/block filesystem, arbitrary
process loading, or a general Grown compiler. The syscall, GWO1 loader, and
compiler preview are narrow validated slices through
`contract -> validation -> implementation -> claim`.
