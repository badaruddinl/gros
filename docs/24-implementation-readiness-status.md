# Implementation Readiness Status

This document records which non-documentation work is currently allowed to start
after the status documents have been completed. It is a gate status document
only. It is not a planning document and does not add a parser, compiler,
interpreter, linker, allocator, executable loader, kernel implementation,
hosted-native output, profile version bump, or boot banner change.

## Purpose

The documentation phase has established status boundaries for the current boot,
runtime, ABI, profile, artifact, and future kernel layers. This document states
which implementation work may start without breaking those boundaries.

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
| GrCall services | `docs/17-grcall-service-registry.md` |
| Profiles | `docs/18-profile-registry.md` |
| Grogan kernel boundary | `docs/19-grogan-kernel-seed.md` |
| GrRT16 runtime status | `docs/20-grrt16-runtime-status.md` |
| GrBoot boot chain status | `docs/21-grboot-boot-chain-status.md` |
| GrABI contract status | `docs/22-grabi-contract-status.md` |
| GWO artifact status | `docs/23-gwo-artifact-status.md` |

This coverage is sufficient for validation-only implementation work around
artifact classification. It is not sufficient to begin compiler, loader, kernel,
or hosted-native executable implementation.

## Implemented Gate

The following implementation class is now present:

```txt
validation-only Bash tooling for headered .gwo candidate fixtures
```

Allowed properties:

- Bash-only,
- no payload execution,
- no boot-time header loading,
- no stage-1 behavior change,
- no `.grw` parser or compiler,
- no generated-code claim,
- no version bump,
- direct byte validation over fixture files.

The first implementation class uses:

- headered `.gwo` candidate fixtures,
- manifests describing expected header checks,
- a Bash validator for those fixtures,
- a Makefile validation target that runs locally,
- policy coverage that keeps the fixtures from being mistaken for bootable
  artifacts.

## Closed Gates

The following gates remain closed:

| Work Class | Status |
| --- | --- |
| `.grw` parser | closed |
| `.grw` compiler | closed |
| `.grw` interpreter | closed |
| generated `.gwn` output | closed |
| generated `.gwo` output claim | closed |
| header-aware `.gwo` executable loader | closed |
| GrBoot header loading | closed |
| Grogan kernel implementation | closed |
| new GrCall runtime services | closed until selector contract and validation are updated |
| heap allocator | closed |
| protected mode | closed |
| long mode | closed |
| UEFI profile | closed |
| hosted-native executable output | closed |

## Validation Requirements

The implemented validation-only class must preserve the current validation baseline:

```bash
make validate
make gwo-header-fixtures
make smoke-stage2
```

It must also include direct checks for:

- docs-only gates remaining intact where applicable,
- no changes to current boot artifacts unless explicitly intended,
- current `build/` artifacts matching committed `dist/` artifacts,
- malformed header fixture rejection,
- raw-profile artifact separation,
- no legacy extension names.

Any new validation target must be runnable locally under WSL/Bash.

## Required Non-Claims

Validation-only implementation must not claim:

- headered `.gwo` execution,
- accepted payload transfer,
- boot-time header classification,
- `.grw` compilation,
- generated `.gwo` production,
- Grogan kernel implementation,
- a complete syscall ABI,
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

This status document does not add:

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
