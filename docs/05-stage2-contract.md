# Stage-1 to Stage-2 Boot Contract

This document defines the first stable technical contract between the GrOS stage-1 boot sector and the first stage-2 payload. It is a build and runtime boundary, not a language or kernel ABI.

## Scope

This contract covers:

- BIOS real-mode disk layout.
- Stage-2 load address and jump target.
- Register and segment state at stage-2 entry.
- Size limits for the first stage-2 implementation.
- Validation requirements for the stage-1 loader path.

This contract does not define:

- A final kernel ABI.
- A filesystem format.
- A Grown `.grw` compiler or interpreter.
- A version bump from the current GrOS v0.5 boot banner.

## Image Layout

The bootable `.gwo` image is laid out in 512-byte sectors:

```txt
LBA 0  / CHS 0:0:1  stage-1 boot sector
LBA 1  / CHS 0:0:2  stage-2 sector 0
LBA 2  / CHS 0:0:3  stage-2 sector 1
LBA 3  / CHS 0:0:4  stage-2 sector 2
LBA 4  / CHS 0:0:5  stage-2 sector 3
```

Stage-1 remains exactly 512 bytes and ends with the boot signature:

```txt
55 AA
```

The initial stage-2 reservation is 4 sectors, or 2048 bytes. The full image size must be a multiple of 512 bytes.

The reference implementation paths are:

```txt
boot/stage1_loader.gwn
boot/stage2_min.gwn
build/gros-stage2.gwo
dist/gros-stage2.gwo
```

## Load Contract

Stage-1 loads stage-2 with BIOS `int 13h` disk read:

```txt
AH = 02h       BIOS read sectors
AL = 04h       stage-2 sector count
CH = 00h       cylinder 0
CL = 02h       sector 2, because sector 1 is stage-1
DH = 00h       head 0
DL = boot drive, preserved from BIOS entry
ES:BX = 0000:8000
```

The stage-2 physical load address is:

```txt
0x00008000
```

The stage-2 entrypoint is the first byte of the loaded payload:

```txt
0000:8000
```

Stage-1 transfers control with a far jump or an equivalent `CS:IP` transfer to `0000:8000`.

## Entry State

At stage-2 entry:

- CPU mode is 16-bit real mode.
- `CS:IP` points to `0000:8000`.
- `DL` contains the BIOS boot drive.
- `DS`, `ES`, and `SS` are `0000`.
- `SP` is `7C00`.
- Direction flag is clear.

All other registers are undefined and must be initialized by stage-2 before use.

Stage-2 must not assume that stage-1 strings, buffers, or command state remain stable. The only explicit handoff value is `DL`.

## Failure Contract

If the BIOS disk read fails, stage-1 must not jump into the stage-2 load area. The first implementation may print a short error marker and halt or reboot through BIOS.

Stage-2 may assume that every reserved stage-2 sector was read successfully before entry.

## Build Rules

- Stage-1 source remains raw `.gwn`.
- Stage-2 source remains raw `.gwn` for this contract.
- `.gwo` remains a build artifact.
- Bash tooling remains the build path.
- NASM or `ndisasm` may be used for validation only, not as the source of truth for building.

## Validation Requirements

The stage-2 loader implementation must validate:

- Stage-1 output is exactly 512 bytes.
- Stage-1 boot signature is `55aa`.
- Full boot image size is a multiple of 512 bytes.
- Stage-2 starts at LBA 1.
- Stage-2 load target is `0000:8000`.
- Static disassembly shows a BIOS `int 13h` read path.
- QEMU starts the image without an immediate crash.

These checks belong to the v0.5 patch line and must not change the boot banner.
