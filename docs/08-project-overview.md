# Project Overview

This document is a human-readable snapshot of the current GrOS repository structure. The local code-review graph is kept in `.code-review-graph/` and is intentionally ignored by Git because it contains generated database files and machine-local paths.

The generated graph wiki is available locally at:

```txt
.code-review-graph/wiki/index.md
```

## Current Purpose

GrOS is a low-level operating system development repository for the Gr ecosystem. The current runtime target is x86 BIOS real mode.

The active baseline remains:

```txt
GrOS v0.5
```

The boot banner is not bumped by documentation, validation, or spec-only changes.

## File Role Model

```txt
.gr   ground/root/raw low-level source
.gn   future Grown language source
.gro  grown output artifact
```

Current boot and stage code is still written as raw `.gr` source and built with Bash tooling. Grown `.gn` is specified but not implemented as a compiler, interpreter, parser, runtime, or build step.

## Main Directories

```txt
boot/     raw boot and stage source
scripts/  Bash-only build, check, test, and QEMU helpers
dist/     committed reference .gro artifacts
docs/     technical contracts and seed specs
build/    ignored generated build output
```

## Boot Artifacts

The repository currently maintains two important `.gro` outputs.

The legacy v0.5 boot sector:

```txt
boot/grboot_v0_5.gr
dist/gros-v0.5.gro
build/gros-v0.5.gro
```

The stage-2 loader image:

```txt
boot/stage1_loader.gr
boot/stage2_min.gr
dist/gros-stage2.gro
build/gros-stage2.gro
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
.gr source -> scripts/grraw.sh -> .gro artifact
```

The main builder is:

```txt
scripts/grraw.sh
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

- raw builder tests
- v0.5 boot sector size and signature
- stage-2 image size and signature
- committed `dist/` artifact parity
- validation-only `ndisasm` checks
- stage-2 loader handoff requirements

The stage-2 smoke command is:

```bash
make smoke-stage2
```

It starts the stage-2 image under QEMU and fails when QEMU is unavailable.

## Technical Specs

The core technical documents are:

```txt
docs/04-raw-gr-format.md
docs/05-stage2-contract.md
docs/06-abi-handoff.md
docs/07-grown-language.md
```

Their current responsibilities:

- `04-raw-gr-format.md` defines the raw `.gr` source format.
- `05-stage2-contract.md` defines the stage-1 to stage-2 boot contract.
- `06-abi-handoff.md` defines the first machine-level handoff profile.
- `07-grown-language.md` reserves Grown `.gn` and describes the seed language shape.

## Code-Review Graph Snapshot

The rebuilt local graph currently indexes:

```txt
files:     10
nodes:     44
edges:     174
language:  bash
```

The generated graph wiki groups the Bash code mainly around:

- raw `.gr` parsing and emission in `scripts/grraw.sh`
- builder tests in `scripts/test_grraw.sh`
- validation helpers for boot and stage-2 images
- QEMU run and smoke helpers

The graph database and generated wiki are local development aids. They are not source artifacts and should remain outside commits.

## Next Solid Development Step

The next strong technical step is to define a small calling convention and syscall seed contract before any Grown `.gn` implementation work.

That should cover:

- function call register use
- register preservation
- stack frame shape
- syscall or kernel service entry
- failure and halt behavior
- `.gro` executable payload layout
