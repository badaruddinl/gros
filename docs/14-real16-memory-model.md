# Real16 Memory Model Seed

This document defines the first memory model seed for the current GrOS stage-2 runtime profile. It is a technical contract for handwritten `.gr` payload code and future `.gn` lowering constraints. It does not add a compiler, parser, interpreter, linker, heap allocator, executable loader, hosted-native target, or boot banner change.

## Profile

```txt
gros.x86.bios.real16.stage2.v0
```

Current machine mode:

```txt
x86 BIOS real mode, 16-bit
```

This is not an `x86_64` profile.

## Address Model

The seed profile uses real-mode segmented addressing:

```txt
physical = segment * 16 + offset
```

The initial stage-2 runtime keeps the simple flat seed established by the stage-1 handoff:

```txt
CS = 0000
DS = 0000
ES = 0000
SS = 0000
```

Within that seed, a 16-bit near offset maps directly to a physical address in the first 64 KiB. Far pointers, segment arithmetic, relocation records, and address-space switching are reserved.

## Pointer Seed

Near pointers are the only pointer form seeded for the current profile:

```txt
u16 offset within segment 0000
```

Seed rules:

- `DS:offset` is the default data pointer form.
- `SS:SP` is the only stack pointer form.
- `CS:IP` is the code pointer form for the active instruction stream.
- `ES:DI` may be used as a BIOS or low-level copy boundary when a service explicitly defines it.
- Pointer-sized `.gn` types remain reserved until the memory model has static fixtures and at least one generated-code validation path.

Future profiles may introduce far pointers, normalized physical addresses, page-based virtual addresses, or capability-like handles. None of those are part of this seed.

## Reserved Low Memory

The following physical ranges are externally owned or reserved:

```txt
00000h..003FFh  BIOS interrupt vector table
00400h..004FFh  BIOS data area
00500h..06FFFh  reserved scratch and stack headroom for this seed
07000h..07BFFh  reserved stack growth zone
07C00h..07DFFh  stage-1 load area, not stable payload data
07E00h..07FFFh  reserved guard space before stage-2
08000h..087FFh  stage-2 payload image
08800h..09FFFh  reserved stage-2 expansion window
0A000h..0FFFFh  reserved platform and future profile space
```

The seed intentionally reserves more low memory than the current implementation uses. This keeps early code conservative while the ABI, payload format, and runtime services are still being proven.

## Stage-2 Image Region

The current stage-2 image is loaded at:

```txt
0000:8000
```

The current stage-2 payload size is:

```txt
2048 bytes
```

Therefore the current payload image occupies:

```txt
08000h..087FFh
```

Rules:

- Code and static data may live inside the loaded stage-2 image.
- Static strings used by current runtime services are payload-owned only while they remain inside this image.
- Stage-2 must not treat padding bytes as stable data unless the source labels and emitted bytes explicitly define them.
- No relocation, symbol table, or headered payload metadata is active in this seed.

## Stack Region

The stage-2 stack starts from the handoff state:

```txt
SS = 0000
SP = 7C00
```

The stack grows downward. The conservative seed stack region is:

```txt
07000h..07BFFh
```

Rules:

- Stack entries are 16-bit words unless a service explicitly defines byte storage.
- Stage-2 code must keep `SP` below `7C00h` after pushes.
- Stage-2 code must not let the stack grow below `7000h` in this profile seed.
- Stack overflow handling is not implemented.
- There is no stack probing contract.
- Interrupt service handlers must preserve the interrupt return frame shape required by the runtime ABI.

The range `07C00h..07DFFh` contains the stage-1 load area and must not be used as stable stack storage after entry.

## Data Ownership

The current profile has no dynamic memory ownership protocol.

Rules:

- Data is either inside the stage-2 payload image or inside the active stack region.
- Any memory outside those regions must be explicitly initialized before use and must be documented by the service or profile revision that uses it.
- BIOS-owned ranges must not be overwritten.
- Stage-1 internal buffers, labels, and strings are not stage-2 data.
- Cross-service global storage is reserved until a runtime data region is specified.

## Heap Rule

There is no heap in this seed.

The following are intentionally undefined:

- allocator entrypoints
- free lists
- object ownership
- string allocation
- array allocation
- stack-to-heap promotion
- garbage collection

Future `.gn` programs targeting this profile must not require heap allocation until a later GrOS profile defines and validates an allocator or an equivalent static-memory model.

## Grown `.gn` Constraints

This memory model is a seed for future `.gn` lowering only. It does not make `.gn` executable in this repository yet.

Until the ABI stability gate opens, `.gn` profile rules must treat these features as reserved:

- pointer arithmetic
- general references
- arrays requiring runtime bounds metadata
- heap-allocated strings
- dynamic dispatch tables
- stack-allocated objects with layout guarantees
- far pointers
- passing pointers across hosted-native profile boundaries

Allowed for specification examples only:

```gn
target "gros.x86.bios.real16.stage2.v0"

fn main() -> void {
    return;
}
```

This example is not compiled by the current repository.

## Runtime Service Interaction

The current runtime service gate is:

```txt
int 30h
```

Memory-facing service rules:

- `console/text.write_cstr` reads a NUL-terminated byte string from `DS:SI`.
- For the current seed, callers must place that string inside the stage-2 image or another explicitly initialized payload-owned range.
- `console/text.write_char` does not consume a memory pointer.
- Future memory services are reserved under service group `04h`.

The runtime ABI seed remains the source of truth for register inputs, return values, and preservation rules.

## Validation Status

Current status:

```txt
seeded, not stable for generated `.gn` code
```

Existing validation covers:

- stage-1 size and boot signature
- stage-2 image size and load contract
- static memory map boundaries through `scripts/check_memory_model.sh`
- seeded near pointers through `scripts/check_near_pointers.sh`
- runtime ABI byte fixtures
- QEMU stage-2 smoke start

Missing validation:

- generated-code fixture
- payload data-region fixture

These missing checks block `.gn` pointer types and generated `.gro` payloads.

## Non-Goals

This seed does not define:

- protected mode
- long mode
- paging
- virtual memory
- task address spaces
- a kernel heap
- a userspace heap
- dynamic linking
- relocations
- a `.gn` compiler
- hosted-native executable output
- a version bump
