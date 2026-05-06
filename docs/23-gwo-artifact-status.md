# GWO Artifact Status

This document records the current status of `.gwo` artifacts in the GrOS
repository. It is a status and validation map only. It does not add a headered
`.gwo` loader, executable loader, parser, compiler, interpreter, linker,
allocator, kernel implementation, hosted-native output, profile version bump, or
boot banner change.

## Purpose

`.gwo` means Grown Object. In the current repository, `.gwo` is already used for
raw bootable artifacts. A future headered executable `.gwo` class is specified,
but it is not implemented or loaded today.

This document keeps those artifact classes separate before validation tooling or
loader work grows around them.

## Current Status

Current implemented artifact class:

```txt
raw-profile .gwo
```

Current reserved artifact class:

```txt
headered-executable .gwo
```

Status words:

```txt
raw-profile .gwo         implemented seed
headered-executable .gwo reserved/future
```

## Implemented Raw-Profile Artifacts

Current committed raw-profile artifacts:

```txt
dist/gros-v0.5.gwo
dist/gros-stage2.gwo
```

Current generated raw-profile artifacts:

```txt
build/gros-v0.5.gwo
build/gros-stage2.gwo
```

### `gros-v0.5.gwo`

Source:

```txt
boot/grboot_v0_5.gwn
```

Shape:

```txt
512-byte BIOS boot sector
boot signature 55aa
```

This artifact contains the compact v0.5 boot prompt inside one boot sector.

### `gros-stage2.gwo`

Sources:

```txt
boot/stage1_loader.gwn
boot/stage2_min.gwn
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

This artifact is the current GrBoot-to-GrRT16 path. It is still a raw-profile
image, not a headered executable object.

## Raw-Profile Rules

Raw-profile `.gwo` artifacts are valid only because their layout is defined by a
separate profile, boot, or handoff contract.

Current raw-profile contracts:

```txt
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/21-grboot-boot-chain-status.md
docs/22-grabi-contract-status.md
```

Raw-profile artifacts do not carry:

```txt
header magic
header size
header version
profile_id
flags
entry offset
payload size
payload checksum
```

Tools must not treat a current raw-profile artifact as a malformed headered
artifact.

## Headered Executable Boundary

The future headered executable `.gwo` seed is defined by:

```txt
docs/11-gwo-payload-header.md
```

Headered executable `.gwo` payloads are reserved for future GrOS execution and
tooling. They require explicit validation before any loader accepts them.

Current status:

```txt
header shape specified
numeric profile_id mapping not assigned
header-aware loader not implemented
headered execution not implemented
generated .grw output not implemented
```

The current stage-1 loader is raw-profile only. It must not be described as a
header-aware `.gwo` executable loader.

## Header Validation Readiness

Validation-only tooling exists before a loader exists and follows these rules:

- it must inspect bytes without transferring control,
- it must reject malformed header candidates,
- it must keep raw-profile artifacts separate from headered artifacts,
- it must not make stage-1 header-aware,
- it must not claim executable loading,
- it must remain Bash-only unless a future repository contract changes the build
  dependency rule.

The first validation-only header checks cover:

- magic bytes,
- header size,
- header version,
- flags,
- reserved bytes,
- declared payload size,
- entry offset bounds,
- profile identifier placeholder policy.

These checks are validation readiness only. They do not execute a payload.

## Artifact Validation Map

Current raw-profile validation:

| Check | Artifact Class |
| --- | --- |
| `scripts/check_boot.sh` | raw 512-byte boot sector |
| `scripts/validate_boot_image.sh` | raw 512-byte boot sector |
| `scripts/check_stage2_image.sh` | raw stage-1 plus stage-2 boot image |
| `scripts/check_runtime_abi.sh` | raw stage-2 runtime ABI bytes |
| `scripts/check_memory_model.sh` | raw stage-2 memory model bytes |
| `scripts/check_near_pointers.sh` | raw stage-2 near-pointer bytes |
| `scripts/check_stage2_data.sh` | raw stage-2 static data bytes |
| `scripts/check_generated_fixtures.sh` | expected-only generated-code fixture artifacts |
| `scripts/check_gwo_header_fixtures.sh` | headered `.gwo` candidate fixture bytes |

The full current validation path remains:

```bash
make validate
make gwo-header-fixtures
make smoke-stage2
```

The header fixture validator is validation-only. It does not make GrBoot,
GrRT16, or any future loader accept a headered payload.

## Relationship To Grown

Future Grown `.grw` tooling may eventually produce `.gwn` and `.gwo` outputs.
That is not implemented today.

Current build truth remains:

```txt
.gwn source -> Bash raw builder -> .gwo artifact
```

Expected generated-code fixtures may contain `.gwo` bytes as future output
expectations, but they are not compiler output today.

## Change Rules

- A raw-profile artifact layout change must update its boot or handoff contract
  before the artifact changes.
- A headered executable artifact change must update
  `docs/11-gwo-payload-header.md` before validation or loader work depends on
  it.
- A header-aware loader must reject malformed headers before any accepted
  transfer path exists.
- A generated `.gwo` claim must wait for `.grw` tooling and generated-code
  fixture validation.
- Current `dist/` artifacts must remain reproducible from source and match
  generated `build/` artifacts.

## Non-Goals

This status document does not add:

- a header to current `.gwo` artifacts,
- a headered `.gwo` executable loader,
- executable payload classification at boot time,
- profile ID numeric mapping,
- relocation records,
- symbol tables,
- dynamic linking,
- `.grw` parser,
- `.grw` compiler,
- `.grw` interpreter,
- generated `.gwn`,
- generated `.gwo`,
- Grogan kernel implementation,
- hosted-native executable output,
- protected mode,
- long mode,
- UEFI loading,
- `x86_64` execution,
- a profile version bump,
- a GrOS boot banner change.
