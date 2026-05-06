# GrABI Contract Status

This document records the current status of GrABI, the contract layer for GrOS
machine handoff, runtime calling rules, memory rules, profile identity, and
validation gates. It is a status and validation map only. It does not add a boot
implementation, runtime service, kernel implementation, parser, compiler,
interpreter, linker, allocator, executable loader, hosted-native output, profile
version bump, or boot banner change.

## Purpose

GrABI defines the contracts that GrBoot, GrRT16, future Grogan code, and future
Grown tooling must obey. It is the place where machine state, profile identity,
calling rules, memory rules, and validation requirements are named before code
depends on them.

Current status:

```txt
GrABI: seed/spec with validation
```

The current GrOS baseline remains:

```txt
GrOS v0.5
ground>
```

## Current Profile Stack

Current public runtime profile:

```txt
gros.x86.bios.real16.stage2.v0
```

Backing machine handoff profile:

```txt
x86.bios.real16.stage2.v0
```

Machine environment:

```txt
x86 BIOS real mode
16-bit
stage-2 entry at 0000:8000
```

This is not an `x86_64` profile, not UEFI, and not Grogan proper.

## Contract Status Table

| Area | Current Status | Source Of Truth |
| --- | --- | --- |
| Stage-1 to stage-2 handoff | seed/spec with validation | `docs/05-stage2-contract.md`, `docs/06-abi-handoff.md` |
| Runtime profile identity | implemented seed | `docs/18-profile-registry.md` |
| Function calling convention | seed/spec | `docs/10-runtime-abi-seed.md` |
| GrSCall entry and return convention | implemented seed | `docs/10-runtime-abi-seed.md`, `docs/17-grscall-service-registry.md` |
| Real16 memory model | seed/spec with validation | `docs/14-real16-memory-model.md` |
| `.gwo` raw-profile boundary | implemented for current boot artifacts | `docs/11-gwo-payload-header.md`, `docs/21-grboot-boot-chain-status.md` |
| Headered `.gwo` executable boundary | reserved/future | `docs/11-gwo-payload-header.md` |
| Generated `.grw` code ABI | reserved/future | `docs/13-abi-stability-gate.md`, `docs/15-generated-code-fixture-contract.md` |

## Handoff Contract

The current handoff contract covers the state after GrBoot stage-1 transfers to
the stage-2 payload.

Stable current entry state:

```txt
CS:IP = 0000:8000
DS = 0000
ES = 0000
SS = 0000
SP = 7C00
SS:SP = 0000:7C00
DL = BIOS boot drive
DF clear
```

The only stable handoff data value is:

```txt
DL = BIOS boot drive
```

All other registers and flags are undefined. Stage-2 code must initialize them
before use.

The handoff is a boot/runtime boundary. It is not a complete kernel ABI,
filesystem ABI, process ABI, or generated Grown ABI.

## Runtime ABI Seed

The current runtime ABI seed defines:

- argument register seed,
- return register seed,
- caller-saved and callee-saved register seed,
- stack rules,
- runtime service gate shape,
- GrSCall selector shape,
- success and error return convention.

Current calling convention seed:

```txt
AX BX CX DX  arguments 0..3
AX           primary return value
DX:AX        optional 32-bit return value when a profile requires it
AX BX CX DX FLAGS  caller-saved
SI DI BP SP DS ES SS  callee-saved
```

Direction flag must be clear on function entry and return.

Current GrSCall gate:

```txt
int 30h
```

Current selector encoding:

```txt
AH = service group
AL = service id
```

Current return convention:

```txt
CF = 0  success, AX = result
CF = 1  error,   AX = error code
```

Unsupported selectors return:

```txt
CF = 1
AX = 0001h
```

Implemented services are tracked by:

```txt
docs/17-grscall-service-registry.md
```

GrABI defines the call and return shape. GrSCall owns the service namespace and
selector stability rules.

## Memory Contract

The current real16 memory seed defines:

- real-mode segmented addressing,
- near-pointer seed,
- stack range,
- stage-1 load area boundary,
- stage-2 payload image range,
- reserved low-memory ranges,
- no-heap rule.

Important current ranges:

```txt
07000h..07BFFh  conservative stack region
07C00h..07DFFh  stage-1 load area, not stable runtime data
08000h..087FFh  stage-2 payload image
```

There is no allocator, heap, paging, virtual address space, relocation model, or
far-pointer ABI in the current seed.

## Validation Status

GrABI status is validated through static fixtures over the built `.gwo` images.

| Validation | Current Evidence |
| --- | --- |
| Boot handoff | `scripts/check_stage2_image.sh` |
| Runtime ABI | `scripts/check_runtime_abi.sh` |
| Memory model | `scripts/check_memory_model.sh` |
| Near pointers | `scripts/check_near_pointers.sh` |
| Static stage-2 data | `scripts/check_stage2_data.sh` |
| Generated-code fixture metadata | `scripts/check_generated_fixtures.sh` |
| QEMU smoke | `scripts/smoke_stage2_qemu.sh` |

The full local validation path remains:

```bash
make validate
make smoke-stage2
```

## Compiler Gate Status

GrABI is not stable enough for `.grw` compiler implementation yet.

Current blockers:

- generated-code fixture coverage is expected-only,
- headered `.gwo` execution is not implemented,
- payload loading for generated executable objects is not implemented,
- memory model is static and has no heap or pointer-width contract beyond the
  current real16 near-pointer seed,
- runtime services are intentionally minimal.

The compiler gate is defined by:

```txt
docs/13-abi-stability-gate.md
```

## Layer Boundaries

GrABI is a contract layer.

It does not own:

- GrBoot source implementation,
- GrRT16 prompt/runtime behavior,
- GrSCall selector namespace ownership,
- Grogan kernel state,
- `.grw` parsing or code generation,
- `.gwo` executable loading.

Current relationship:

```txt
GrBoot implements boot transfer.
GrRT16 implements the current runtime seed.
GrSCall names service selectors.
GrABI defines the contracts those layers must obey.
Grogan remains reserved/future.
```

## Change Rules

Changes to GrABI must follow:

```txt
contract -> validation -> implementation -> claim
```

Rules:

- A register contract change must update runtime ABI docs and byte validation.
- A handoff change must update boot contract docs, GrBoot status, GrRT16 status,
  and stage-2 image validation.
- A memory boundary change must update the memory model before code depends on
  it.
- A new profile must be listed in the profile registry with explicit status.
- A generated-code ABI claim must wait until the ABI stability gate opens.
- A headered `.gwo` ABI claim must wait until loader rejection and acceptance
  behavior exists.

## Relationship To Status Documents

Relevant source-of-truth documents:

```txt
docs/00-naming.md
docs/01-ecosystem-map.md
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/10-runtime-abi-seed.md
docs/11-gwo-payload-header.md
docs/13-abi-stability-gate.md
docs/14-real16-memory-model.md
docs/15-generated-code-fixture-contract.md
docs/17-grscall-service-registry.md
docs/18-profile-registry.md
docs/20-grrt16-runtime-status.md
docs/21-grboot-boot-chain-status.md
docs/23-gwo-artifact-status.md
docs/24-implementation-readiness-status.md
```

This document summarizes current GrABI status. It does not override those
contracts.

## Non-Goals

GrABI status does not add:

- a boot implementation,
- a runtime service implementation,
- a complete syscall ABI,
- a Grogan kernel implementation,
- user/kernel separation,
- process, task, or thread ABI,
- heap allocator,
- virtual memory,
- paging,
- protected mode,
- long mode,
- UEFI loading,
- `x86_64` execution,
- headered `.gwo` executable loading,
- `.grw` parser,
- `.grw` compiler,
- `.grw` interpreter,
- generated `.gwn`,
- generated `.gwo`,
- hosted-native executable output,
- a profile version bump,
- a GrOS boot banner change.
