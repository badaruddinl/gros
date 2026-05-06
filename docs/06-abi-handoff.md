# GrOS ABI Handoff Profile

This document defines the first machine-level handoff profile for GrOS payloads. It is a low-level runtime contract for the loaded `.gwo` image. It is not a Grown `.grw` language ABI, compiler spec, filesystem format, or roadmap.

## Profile

```txt
x86.bios.real16.stage2.v0
```

This profile targets:

Here, target means the GrOS machine/profile environment named by the profile. It does not mean Windows, Linux, macOS, or Android priority.

- x86 BIOS firmware.
- 16-bit real mode.
- A raw sector-backed `.gwo` image.
- A stage-2 payload loaded by the GrOS stage-1 boot sector.

## Image Layout

All sectors are 512 bytes.

```txt
LBA 0     stage-1 boot sector
LBA 1..4  stage-2 payload
```

Required sizes:

- Stage-1 is exactly 512 bytes.
- Stage-1 signature at offset 510 is `55 aa`.
- Stage-2 is exactly 2048 bytes in this profile.
- Full image size is exactly 2560 bytes and sector-aligned.

The current reference artifact is:

```txt
dist/gros-stage2.gwo
```

## Load And Entry

Stage-1 loads stage-2 to physical address:

```txt
0x00008000
```

Stage-2 entry is:

```txt
CS:IP = 0000:8000
```

The loader must complete the full stage-2 sector read before transferring control. If the disk read fails, the loader must not jump into the stage-2 load area.

## Entry State

At stage-2 entry:

- `CS:IP = 0000:8000`
- `DS = 0000`
- `ES = 0000`
- `SS = 0000`
- `SP = 7C00`
- `DL = BIOS boot drive`
- Direction flag is clear.
- Interrupts are enabled.

All other registers and flags are undefined. Stage-2 must initialize them before use.

## Handoff Data

This profile has no structured handoff block.

The only stable handoff value is:

```txt
DL = BIOS boot drive
```

Stage-2 must not depend on stage-1 labels, strings, command buffers, padding bytes, or internal temporary state.

## Memory Ownership

Reserved or externally owned regions:

```txt
0000:0000..03ff  BIOS interrupt vector table
0000:0400..04ff  BIOS data area
0000:7c00..7dff  stage-1 load area, not stable payload data
0000:8000..87ff  stage-2 payload image
```

The stack starts at `0000:7C00` and grows downward. Stage-2 owns stack discipline after entry.

Any memory outside the payload image and stack must be explicitly initialized by the stage-2 payload before use.

## BIOS Interface Rules

Stage-2 may use BIOS interrupts while it remains in real mode.

Rules:

- Preserve or deliberately reload `DL` before BIOS disk calls.
- Treat BIOS failure through BIOS-defined flags and registers.
- Do not assume GrOS syscall wrappers exist.
- Do not assume a return path to stage-1.

Returning from the stage-2 entrypoint is undefined.

## Not Yet Defined

The following are intentionally not defined by this profile:

- Function calling convention.
- Register preservation convention.
- Kernel syscall table.
- Heap or allocator contract.
- Object layout.
- Executable `.gwo` subformat.
- Grown `.grw` runtime mapping.

These must be defined before a complete native `.grw` implementation and runtime mapping can produce more than raw GrOS payload output.

## Validation

The profile is validated by:

```bash
make validate
make smoke-stage2
```

The current GrBoot status for this handoff path is summarized in:

```txt
docs/21-grboot-boot-chain-status.md
```

The current GrABI contract status is summarized in:

```txt
docs/22-grabi-contract-status.md
```

Validation must prove:

- Stage-1 size is 512 bytes.
- Stage-1 boot signature is `55aa`.
- Full image size is 2560 bytes.
- Stage-2 starts at LBA 1.
- Stage-2 loads to `0000:8000`.
- Stage-1 uses BIOS `int 13h` for the stage-2 disk read.
- `DL` is reloaded from the saved boot drive before stage-2 entry.
- QEMU starts the stage-2 image without an immediate crash.
