# Implementation Readiness Status

This document records which non-documentation work is currently allowed to start
after the status documents have been completed. It is a gate status document
only. It is not a planning document and does not add a general parser/compiler,
interpreter, linker, allocator, general executable loader, kernel implementation,
hosted-native output, profile version bump, or boot banner change.

## Purpose

The documentation phase has established status boundaries for the current boot,
runtime, ABI, profile, artifact, and future kernel layers. This document states
which implementation work may start without breaking those boundaries. Later
validated bootstrap seeds are recorded here without being promoted to complete
kernel, allocator, scheduler, filesystem, or compiler claims.

The rule remains:

```txt
contract -> validation -> implementation -> claim
```

## Current Documentation Coverage

The current status coverage is:

| Area | Status Document |
| --- | --- |
| Names and status words | `docs/00-naming.md` |
| Ecosystem layers | `docs/01-ecosystem-map.md` |
| Grown/GWN/GWO file roles | `docs/02-grw-gwo-gwn.md` |
| Stage-1 to stage-2 contract | `docs/05-stage2-contract.md` |
| ABI handoff profile | `docs/06-abi-handoff.md` |
| Grown language seed | `docs/07-grown-language.md` |
| Hosted/native ecosystem mapping | `docs/09-grown-ecosystem-mapping.md` |
| Runtime ABI seed | `docs/10-runtime-abi-seed.md` |
| `.gwo` payload header seed | `docs/11-gwo-payload-header.md` |
| `.grw` front-end seed | `docs/12-grw-front-end-seed.md` |
| ABI stability gate | `docs/13-abi-stability-gate.md` |
| Real16 memory model | `docs/14-real16-memory-model.md` |
| Generated-code fixtures | `docs/15-generated-code-fixture-contract.md` |
| Minimal Grown `main` contract | `docs/16-grown-main-runtime-contract.md` |
| GrSCall services | `docs/17-grscall-service-registry.md` |
| Profiles | `docs/18-profile-registry.md` |
| Grogan kernel boundary | `docs/19-grogan-kernel-seed.md` |
| GrRT16 runtime status | `docs/20-grrt16-runtime-status.md` |
| GrBoot boot chain status | `docs/21-grboot-boot-chain-status.md` |
| GrABI contract status | `docs/22-grabi-contract-status.md` |
| GWO artifact status | `docs/23-gwo-artifact-status.md` |
| BIOS-to-x86_64 transition | `docs/32-long-mode-transition-contract.md` |
| x86_64 exception foundation | `docs/33-x86_64-exception-interrupt-foundation.md` |
| Physical-memory ownership | `docs/34-physical-memory-ownership.md` |
| Kernel heap seed | `docs/35-kernel-heap-seed.md` |
| Cooperative scheduler seed | `docs/36-cooperative-scheduler-seed.md` |
| Boot-resident filesystem seed | `docs/37-boot-filesystem-seed.md` |
| Grogan x86_64 product profile | `docs/38-grogan-x86_64-profile.md` |
| Grogan syscall/user boundary | `docs/39-grogan-syscall-user-boundary.md` |
| Grogan compiler preview | `docs/40-grogan-compiler-preview.md` |

This coverage is sufficient for the deliberately tiny minimal-main and Grogan
compiler slices, plus their bounded loader and syscall evidence. It is not
sufficient to begin general compiler, loader, kernel, or hosted-native
executable implementation.

## Implemented Gate

The following validation-only implementation classes are now present:

```txt
validation-only Bash tooling for headered .gwo candidate fixtures
validation-only Bash tooling for expected generated-code ABI fixtures
minimal-main `.grw` subset compiler and headered boot proof
bounded Grogan x86_64 `.grw` compiler, GWO1 loader, and syscall/user proof
```

Allowed properties:

- Bash-only,
- payload execution only for the fixed stage-2 reservation,
- fixed boot-time header validation only,
- no stage-1 behavior change,
- no general `.grw` parser or compiler,
- no general generated-code claim,
- no arbitrary GWO1 file loading or relocation,
- no version bump,
- direct byte validation over fixture files.

The first implementation class uses:

- headered `.gwo` candidate fixtures,
- manifests describing expected header checks,
- a Bash validator for those fixtures,
- a Makefile validation target that runs locally,
- policy coverage that keeps the fixtures from being mistaken for bootable
  artifacts.

The generated-code compatibility class uses:

- expected-only ABI fixture source that is not parsed or compiled,
- handwritten expected `.gwn` and golden `.gwo` bytes,
- a direct-call convention fixture for `grabi.real16.call.v1`,
- byte-level validation of register arguments, stack cleanup, return, DF, and
  callee preservation,
- no payload execution, loader behavior, or compiler-output claim.

The later bootstrap seed classes are also implemented and validated in narrow
scope:

```txt
BIOS-to-x86_64 transition and boot-info/E820 discovery
x86_64 IDT installation with fail-stop exception proof
PIC/PIT remap with timer and keyboard IRQ stubs
bounded two-window paging and E820-backed physical-frame pool
bounded one-frame bitmap heap with free/reuse
heap-backed timer-preemptive task contexts with shell round-robin return
boot-resident read-only filesystem lookup and read
```

The fixed stage-2 loader implemented in the earlier gate remains unchanged;
the new GWO1 loader is an additional bounded Grogan path.

These seeds establish evidence-backed boundaries. They do not open the general
kernel, allocator, filesystem, interrupt-device, or userspace gates; the
preemptive scheduler gate is open only for the two bounded kernel task contexts.

## Closed Gates

The following gates remain closed:

| Work Class | Status |
| --- | --- |
| general `.grw` parser | closed (minimal-main lexical subset implemented) |
| general `.grw` compiler | closed (minimal-main and Grogan preview subsets implemented) |
| `.grw` interpreter | closed |
| general generated `.gwn` output | closed |
| general generated `.gwo` output claim | closed |
| general header-aware `.gwo` executable loader | closed (fixed stage-2 and bounded GWO1 loaders implemented) |
| general GrBoot header loading | closed (fixed stage-2 reservation implemented) |
| general Grogan kernel implementation | closed (real16 and x86_64 bootstrap seeds implemented) |
| new GrSCall runtime services | closed until selector contract and validation are updated |
| general physical-frame allocator | closed (bounded 64-frame pool implemented) |
| general paging manager | closed (bounded second 2 MiB identity window implemented) |
| general heap allocator | closed (bounded one-frame bitmap heap with free/reuse implemented) |
| protected mode runtime | closed (transition seed only) |
| long mode runtime | closed (transition and IDT seeds only) |
| general hardware IRQ/device model | closed (initial PIC/PIT timer and keyboard seed implemented) |
| recoverable exception handling | closed (fail-stop handler seed implemented) |
| general scheduler | closed (bounded timer-preemptive two-task context seed implemented) |
| general filesystem | closed (boot-resident read-only seed implemented) |
| process and userspace model | closed (bounded DPL3 smoke payload only) |
| UEFI profile | closed |
| hosted-native executable output | closed |

## Validation Requirements

The implemented validation-only class must preserve the current validation baseline:

```bash
make validate-static
make validate-qemu
make validate-release
make gwo-header-fixtures
```

`make validate` remains a compatibility alias for `make validate-static`.
The static lane contains byte checks and negative self-tests; the QEMU lane
contains only positive emulator traces; the release lane runs both and reports
their individual durations.

It must also include direct checks for:

- docs-only gates remaining intact where applicable,
- no changes to current boot artifacts unless explicitly intended,
- current `build/` artifacts matching committed `dist/` artifacts,
- malformed header fixture rejection,
- raw-profile artifact separation,
- no legacy extension names.

Any new validation target must be runnable locally under WSL/Bash.

## Required Non-Claims

Implementation outside the minimal-main subset must not claim:

- headered `.gwo` execution,
- accepted payload transfer,
- boot-time header classification,
- general `.grw` compilation,
- general generated `.gwo` production beyond the bounded Grogan smoke artifact,
- arbitrary GWO1 loading, relocation, or process creation,
- Grogan kernel implementation,
- a complete syscall ABI,
- general physical-frame allocation, paging, or heap behavior beyond bounded seeds,
- general hardware IRQ/device delivery or recoverable exception handling,
- general preemptive scheduling beyond the two bounded contexts, task isolation, or a process model,
- a general filesystem or block-device driver,
- hosted-native executable output.

## Transition Rule

After the first validation-only implementation lands, later changes may proceed
only by opening the next gate with the same order:

```txt
contract -> validation -> implementation -> claim
```

If a component lacks validation, it must remain `seed/spec` or
`reserved/future`.

## Non-Goals

This status document does not add a complete implementation of:

- a parser,
- a compiler,
- an interpreter,
- a linker,
- an allocator,
- an executable loader,
- a kernel implementation,
- a hosted-native executable backend,
- a new runtime service,
- a new boot path,
- a profile version bump,
- a GrOS boot banner change.
