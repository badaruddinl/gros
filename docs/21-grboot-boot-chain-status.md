# GrBoot Boot Chain Status

This document records the current implemented status of GrBoot, the boot chain
and bootloader layer for the GrOS repository. It is a status and validation map
only. It does not add a new boot path, executable `.gwo` loader, kernel
implementation, parser, compiler, interpreter, linker, allocator, hosted-native
output, UEFI target, `x86_64` execution, profile version bump, or boot banner
change.

## Purpose

GrBoot owns the current bootable raw-profile `.gwo` images and the first
transfer of control into GrOS runtime code. It proves that GrOS can start from
BIOS-loaded bytes before Grogan, headered `.gwo` execution, generated Grown
code, or richer platform profiles exist.

Current status:

```txt
GrBoot: implemented seed
```

Current visible baseline:

```txt
GrOS v0.5
ground>
```

## Current Machine Profile

GrBoot currently targets:

```txt
x86 BIOS real mode
16-bit
512-byte sectors
```

The current GrOS runtime profile reached by the stage-2 boot chain is:

```txt
gros.x86.bios.real16.stage2.v0
```

This is not an `x86_64` profile and not UEFI.

## Implemented Boot Artifacts

GrBoot currently has two bootable raw-profile `.gwo` artifacts.

### Single-Sector v0.5 Boot Artifact

Source:

```txt
boot/grboot_v0_5.gwn
```

Artifacts:

```txt
build/gros-v0.5.gwo
dist/gros-v0.5.gwo
```

Shape:

```txt
512-byte BIOS boot sector
boot signature 55aa
```

This artifact contains the v0.5 prompt directly inside one boot sector. It is a
legacy compact baseline, not Grogan proper and not a headered executable
payload.

### Stage-1 To Stage-2 Boot Artifact

Sources:

```txt
boot/stage1_loader.gwn
boot/stage2_min.gwn
```

Artifacts:

```txt
build/gros-stage2.gwo
dist/gros-stage2.gwo
```

Shape:

```txt
LBA 0     512-byte stage-1 BIOS loader
LBA 1..4  2048-byte stage-2 payload
total     2560 bytes
```

Stage-1 loads stage-2 to:

```txt
0000:8000
```

and transfers control to:

```txt
CS:IP = 0000:8000
```

## Stage-1 Loader Responsibilities

The current stage-1 loader owns:

- BIOS real-mode segment and stack setup before disk access,
- BIOS boot drive preservation,
- BIOS disk reset,
- BIOS `int 13h` sector read for the reserved stage-2 sectors,
- `DL` reload before stage-2 entry,
- transfer to `0000:8000`,
- short disk-error output and halt loop when the read fails.

The stage-1 loader does not own:

- the prompt loop,
- GrSCall service dispatch,
- GrRT16 runtime state,
- Grogan kernel state,
- headered `.gwo` classification,
- filesystem lookup,
- relocation,
- profile negotiation.

## Handoff Contract

The stage-1 to stage-2 handoff is defined by:

```txt
docs/05-stage2-contract.md
docs/06-abi-handoff.md
```

At stage-2 entry, the current stable handoff includes:

```txt
CS:IP = 0000:8000
DS = 0000
ES = 0000
SS = 0000
SP = 7C00
DL = BIOS boot drive
DF clear
```

All other registers and flags are undefined. Stage-2 must initialize them before
use.

The only stable data handoff is:

```txt
DL = BIOS boot drive
```

Stage-2 must not depend on stage-1 strings, labels, buffers, padding bytes, or
temporary state.

## Raw-Profile GWO Boundary

Current GrBoot artifacts are raw-profile `.gwo` images.

They are valid because their layouts are defined by boot and handoff contracts,
not because they carry a `.gwo` executable header.

Current raw-profile artifacts:

```txt
dist/gros-v0.5.gwo
dist/gros-stage2.gwo
```

The current stage-1 loader is not a header-aware `.gwo` executable loader. It
must not be described as one.

The future header boundary is defined by:

```txt
docs/11-gwo-payload-header.md
```

## Validation Map

GrBoot status is validated by direct checks over `.gwn` source and `.gwo`
artifacts.

| Check | What It Protects |
| --- | --- |
| `scripts/build_boot.sh` | reproducible v0.5 boot sector build |
| `scripts/check_boot.sh` | 512-byte size and `55aa` signature |
| `scripts/validate_boot_image.sh` | boot-sector static validation and validation-only disassembly |
| `scripts/build_stage2_image.sh` | reproducible stage-1 plus stage-2 image build |
| `scripts/check_stage2_image.sh` | stage-1 loader read path, stage-2 transfer, image size, signature, prompt bytes |
| `scripts/smoke_stage2_qemu.sh` | QEMU smoke start for the stage-2 boot image |
| `scripts/test_gwnraw.sh` | raw `.gwn` builder behavior and artifact parity |

The full local validation path remains:

```bash
make validate
make smoke-stage2
```

Validated boot facts today:

- `dist/gros-v0.5.gwo` is exactly 512 bytes,
- `dist/gros-v0.5.gwo` ends with `55aa`,
- `dist/gros-stage2.gwo` is exactly 2560 bytes,
- stage-1 in `dist/gros-stage2.gwo` is 512 bytes,
- stage-2 payload reservation is 2048 bytes,
- stage-1 uses BIOS `int 13h` for the stage-2 read,
- stage-1 reloads the boot drive before transfer,
- stage-1 jumps to `0000:8000`,
- build artifacts match committed `dist/` artifacts.

## Change Rules

Changes to GrBoot must keep the boot boundary precise.

Rules:

- A boot image size change must update the relevant boot contract and
  validation before it is claimed.
- A stage-2 load address change must update the stage-2 contract, ABI handoff,
  runtime status, and validation.
- A disk read behavior change must keep the failure contract explicit.
- Headered `.gwo` loading must not be claimed until a header-aware loader
  exists and validates rejection behavior.
- Boot code must remain `.gwn` plus Bash tooling unless a future contract changes
  the build source of truth.
- GrBoot must not be described as Grogan or as the full GrOS kernel.

## Relationship To GrRT16 And Grogan

Current relationship:

```txt
GrBoot loads GrRT16 today.
GrRT16 owns the current real16 runtime seed.
Grogan remains reserved/future.
```

GrRT16 status is defined by:

```txt
docs/20-grrt16-runtime-status.md
```

Grogan seed boundaries are defined by:

```txt
docs/19-grogan-kernel-seed.md
```

## Relationship To Status Documents

Relevant source-of-truth documents:

```txt
docs/00-naming.md
docs/01-ecosystem-map.md
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/08-project-overview.md
docs/11-gwo-payload-header.md
docs/18-profile-registry.md
docs/19-grogan-kernel-seed.md
docs/20-grrt16-runtime-status.md
docs/22-grabi-contract-status.md
docs/23-gwo-artifact-status.md
docs/24-implementation-readiness-status.md
```

This document summarizes current GrBoot status. It does not override those
contracts.

## Non-Goals

GrBoot does not currently provide:

- a Grogan kernel implementation,
- a headered `.gwo` executable loader,
- executable payload classification,
- filesystem loading,
- relocation,
- dynamic linking,
- profile negotiation,
- UEFI loading,
- protected mode,
- long mode,
- `x86_64` execution,
- device driver model,
- storage service API,
- GrSCall dispatch,
- `.grw` parser,
- `.grw` compiler,
- `.grw` interpreter,
- hosted-native executable output,
- a profile version bump,
- a GrOS boot banner change.
