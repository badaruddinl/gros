# Project Overview

This document is a human-readable snapshot of the current GrOS repository structure. The local code-review graph is kept in `.code-review-graph/` and is intentionally ignored by Git because it contains generated database files and machine-local paths.

The generated graph wiki is available locally at:

```txt
.code-review-graph/wiki/index.md
```

## Current Purpose

GrOS is a low-level operating system development repository for the Gr ecosystem. The current runtime profile is `gros.x86.bios.real16.stage2.v0`, an x86 BIOS real-mode profile listed in `docs/18-profile-registry.md`.

The active baseline remains:

```txt
GrOS v0.5
```

The boot banner is not bumped by documentation, validation, or spec-only changes.

## File Role Model

```txt
.grw   Ground Readable Weave, the main Grown source form
.gwo   Grown Object, the compiled/output artifact form
.gwn   Ground/Woven Native, the low-level native/backend layer
```

Current boot and stage code is still written as raw `.gwn` source and built with Bash tooling. Grown `.grw` is the readable native low-level language surface for the GrOS ecosystem; compiler, interpreter, parser, and build integration are not implemented yet.

## Main Directories

```txt
boot/     raw boot and stage source
scripts/  Bash-only build, check, test, and QEMU helpers
dist/     committed reference .gwo artifacts
docs/     technical contracts and seed specs
build/    ignored generated build output
```

## Boot Artifacts

The repository currently maintains two important `.gwo` outputs.

The legacy v0.5 boot sector:

```txt
boot/grboot_v0_5.gwn
dist/gros-v0.5.gwo
build/gros-v0.5.gwo
```

The stage-2 loader image:

```txt
boot/stage1_loader.gwn
boot/stage2_min.gwn
dist/gros-stage2.gwo
build/gros-stage2.gwo
```

The stage-2 image is laid out as:

```txt
LBA 0     512-byte stage-1 BIOS loader
LBA 1..4  2048-byte stage-2 payload
```

Stage-1 loads stage-2 to:

```txt
0000:8000
```

## Build Flow

The active build flow is intentionally small:

```txt
.gwn source -> scripts/gwnraw.sh -> .gwo artifact
```

The main builder is:

```txt
scripts/gwnraw.sh
```

It provides a raw source format with:

- byte emission
- ASCII emission
- labels
- absolute 16-bit label references
- relative 8-bit and 16-bit label references
- padding
- boot signatures

## Validation Flow

The main validation command is:

```bash
make validate
```

It checks:

- project policy rules for local-only and generated files
- generated-code fixture manifests when fixtures exist
- raw builder tests
- v0.5 boot sector size and signature
- stage-2 image size and signature
- committed `dist/` artifact parity
- validation-only `ndisasm` checks
- stage-2 loader handoff requirements
- real16 memory model boundaries
- stage-2 near-pointer immediates
- stage-2 static text/data bytes
- runtime ABI byte fixtures for implemented `int 30h` services

The stage-2 smoke command is:

```bash
make smoke-stage2
```

It starts the stage-2 image under QEMU and fails when QEMU is unavailable.

## Technical Specs

The core technical documents are:

```txt
docs/00-naming.md
docs/01-ecosystem-map.md
docs/02-grw-gwo-gwn.md
docs/03-first-bytes.md
docs/04-raw-gwn-format.md
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/07-grown-language.md
docs/09-grown-ecosystem-mapping.md
docs/10-runtime-abi-seed.md
docs/11-gwo-payload-header.md
docs/12-grw-front-end-seed.md
docs/13-abi-stability-gate.md
docs/14-real16-memory-model.md
docs/15-generated-code-fixture-contract.md
docs/16-grown-main-runtime-contract.md
docs/17-grcall-service-registry.md
docs/18-profile-registry.md
docs/19-grogan-kernel-seed.md
docs/20-grrt16-runtime-status.md
docs/21-grboot-boot-chain-status.md
docs/22-grabi-contract-status.md
docs/23-gwo-artifact-status.md
docs/24-implementation-readiness-status.md
```

Their current responsibilities:

- `00-naming.md` defines official ecosystem terms and status wording.
- `01-ecosystem-map.md` maps implemented, seeded, and reserved layers.
- `02-grw-gwo-gwn.md` defines the source, artifact, and native/backend file roles.
- `03-first-bytes.md` documents the first boot-sector bytes and text layout.
- `04-raw-gwn-format.md` defines the raw `.gwn` source format.
- `05-stage2-contract.md` defines the stage-1 to stage-2 boot contract.
- `06-abi-handoff.md` defines the first machine-level handoff profile.
- `07-grown-language.md` defines Grown as the native low-level GrOS systems language and reserves `.grw`.
- `09-grown-ecosystem-mapping.md` defines how `.grw`, `.gwn`, `.gwo`, and hosted-native profiles map together.
- `10-runtime-abi-seed.md` defines the first calling convention and runtime service seed for the current GrOS profile.
- `11-gwo-payload-header.md` reserves the future header shape for executable `.gwo` payloads.
- `12-grw-front-end-seed.md` reserves the first source front-end shape for `.grw`.
- `13-abi-stability-gate.md` defines the stability gate before `.grw` compiler work can start.
- `14-real16-memory-model.md` defines the first memory model seed for the current real16 stage-2 profile.
- `15-generated-code-fixture-contract.md` defines how expected generated-code fixtures must be represented before compiler work starts.
- `16-grown-main-runtime-contract.md` defines the minimal `fn main()` runtime contract seed.
- `17-grcall-service-registry.md` defines implemented and reserved GrCall selectors.
- `18-profile-registry.md` defines canonical profile names, current implementation status, and reserved future profile namespaces.
- `19-grogan-kernel-seed.md` defines the boundary before any future implementation can be called a Grogan kernel seed.
- `20-grrt16-runtime-status.md` records what the current real16 stage-2 runtime owns and how it is validated.
- `21-grboot-boot-chain-status.md` records what the current boot sector and stage-1 loader own and how they are validated.
- `22-grabi-contract-status.md` records the current handoff, runtime ABI, memory, profile, and validation contract status.
- `23-gwo-artifact-status.md` records current raw-profile `.gwo` artifacts and future headered executable `.gwo` readiness rules.
- `24-implementation-readiness-status.md` records the first validation-only implementation gate and which gates remain closed.

Runtime ABI validation is implemented in:

```txt
scripts/check_generated_fixtures.sh
scripts/check_runtime_abi.sh
```

These are Bash-only validators over expected generated-code fixtures and the built stage-2 `.gwo` image.

Real16 memory model validation is implemented in:

```txt
scripts/check_memory_model.sh
scripts/check_near_pointers.sh
scripts/check_stage2_data.sh
```

These are Bash-only static fixtures over the built stage-2 `.gwo` image and the memory model seed.

Headered `.gwo` candidate validation is implemented in:

```txt
scripts/check_gwo_header_fixtures.sh
```

This is a Bash-only validator over reviewable fixture hex. It rejects malformed
header candidates and does not load, execute, or classify current boot
artifacts as headered executables.

## Code-Review Graph Snapshot

The rebuilt local graph currently indexes:

```txt
files:     10
nodes:     44
edges:     174
language:  bash
```

The generated graph wiki groups the Bash code mainly around:

- raw `.gwn` parsing and emission in `scripts/gwnraw.sh`
- builder tests in `scripts/test_gwnraw.sh`
- validation helpers for boot and stage-2 images
- QEMU run and smoke helpers

The graph database and generated wiki are local development aids. They are not source artifacts and should remain outside commits.

## Current Implementation Gate

The current non-documentation implementation gate is defined in:

```txt
docs/24-implementation-readiness-status.md
```

The first non-documentation implementation class is validation-only Bash
tooling for headered `.gwo` candidate fixtures. It must not execute payloads,
make GrBoot
header-aware, claim `.grw` compiler output, implement Grogan, add hosted-native
output, or change the `GrOS v0.5` boot banner.

The current stage-1 loader remains raw-profile only. Headered execution requires
a separate explicit loader contract, acceptance path, rejection path, profile
compatibility rule, and validation before any execution claim can be made.
