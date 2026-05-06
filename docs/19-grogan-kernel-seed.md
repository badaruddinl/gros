# Grogan Kernel Seed

This document defines the seed boundary for Grogan, the future GrOS kernel
proper. It is a status and technical contract document only. It does not add a
kernel implementation, parser, compiler, interpreter, linker, allocator,
executable loader, hosted-native output, profile version bump, or boot banner
change.

## Purpose

Grogan is the reserved name for the kernel proper inside the GrOS ecosystem. The
current repository has GrBoot and GrRT16, but it does not have Grogan proper.

Current status:

```txt
Grogan: reserved/future
```

The purpose of this seed is to define what must become true before any future
stage, runtime, or kernel entrypoint can be called a Grogan seed.

## Current Visible Baseline

The visible GrOS baseline remains:

```txt
GrOS v0.5
ground>
```

This document does not change that banner or prompt.

## Current Boundary

Implemented today:

```txt
GrBoot  loads the current stage-2 image
GrRT16  owns the current real16 prompt/runtime seed
GrABI   defines current machine, handoff, calling, memory, and profile contracts
GrCall  exposes the current runtime service-call seed through int 30h
```

Reserved today:

```txt
Grogan  future GrOS kernel proper
```

The current concrete runtime profile remains:

```txt
gros.x86.bios.real16.stage2.v0
```

This is an x86 BIOS real-mode profile. It is not `x86_64`, not UEFI, and not
Grogan proper.

## Layer Responsibilities

### GrBoot

GrBoot owns bootstrapping and transfer of control into the loaded payload.

Current responsibilities:

- 512-byte BIOS boot sector.
- stage-1 BIOS loader.
- stage-2 load from disk.
- transfer to the stage-2 entrypoint.

GrBoot must not be described as the kernel. It may load a future Grogan image,
but loading the image is not the same as being Grogan.

### GrRT16

GrRT16 owns the current real-mode stage-2 runtime seed.

Current responsibilities:

- prompt loop,
- basic command handling,
- `int 30h` runtime service gate installation,
- implemented GrCall seed services,
- static runtime ABI, memory, pointer, and data validation targets.

GrRT16 may become a host for early Grogan experiments, but GrRT16 by itself is
not Grogan proper.

### GrABI

GrABI owns the machine and runtime contracts that future Grogan code must obey.

Current responsibilities:

- stage-1 to stage-2 handoff state,
- runtime profile identity,
- calling convention seed,
- register preservation seed,
- real16 memory model seed,
- `.gwo` payload boundary rules.

Grogan must depend on explicit GrABI contracts, not on accidental loader state.

### GrCall

GrCall owns the service-call interface shape.

Current entry mechanism:

```txt
int 30h
```

Current implemented services:

```txt
00h:00h runtime/control.probe
01h:00h console/text.write_cstr
01h:01h console/text.write_char
```

A future Grogan seed may own the dispatch implementation behind GrCall, but it
must not change the meaning of already implemented selectors.

## Grogan Seed Admission Gate

The project may call a future implementation a Grogan seed only when all of the
following are true.

### 1. Kernel Entry Contract

The seed must document:

- profile name,
- physical load address,
- physical entrypoint,
- required register state,
- stack state,
- interrupt state,
- direction flag state,
- return behavior.

The current handoff contract is defined by:

```txt
docs/05-stage2-contract.md
docs/06-abi-handoff.md
```

### 2. Machine Ownership Contract

The seed must document which machine resources Grogan owns after entry.

At minimum, that contract must cover:

- interrupt vector ownership,
- BIOS interface policy,
- memory ranges owned by the kernel,
- memory ranges externally owned by firmware or loader code,
- stack ownership,
- static data ownership,
- shutdown, halt, or panic behavior.

The current real16 memory seed is defined by:

```txt
docs/14-real16-memory-model.md
```

### 3. GrCall Dispatch Ownership

The seed must document whether Grogan owns the GrCall dispatch path.

If Grogan owns GrCall dispatch, the seed must preserve:

- selector encoding,
- success and error return convention,
- unsupported selector behavior,
- implemented selector meanings,
- register preservation rules per service.

The current service registry is:

```txt
docs/17-grcall-service-registry.md
```

### 4. Kernel State Contract

The seed must document the first kernel-owned state.

Examples of kernel state are:

- runtime profile descriptor,
- service dispatch table,
- memory map seed,
- panic record,
- device or console descriptor,
- task or execution context record.

None of these are implemented as Grogan-owned kernel structures today.

### 5. Validation Contract

The seed must have validation before it is described as implemented.

Required validation shape:

- source and artifact generation remain reproducible,
- stage image size and boot signature remain validated when applicable,
- entry bytes or transfer path are statically checked,
- GrCall selectors remain byte-validated when implemented,
- memory ownership boundaries are checked,
- QEMU smoke start remains green for bootable profiles.

The validation rule is:

```txt
contract -> validation -> implementation -> claim
```

## First Grogan Seed Shape

The first acceptable Grogan seed should be narrow. It should not start by adding
a full scheduler, filesystem, process model, or compiler dependency.

The first seed may be only:

- a named kernel entry boundary,
- a minimal kernel-owned state block,
- a panic or halt policy,
- explicit ownership of the GrCall dispatch path,
- static validation proving the boundary.

Until those exist, Grogan remains `reserved/future`.

## Relationship To Grown

Grown `.grw` is the future native low-level systems language for GrOS.

Grogan may eventually be written partly or entirely in Grown, lowered through
`.gwn`, and emitted as `.gwo`. That is not implemented today.

Current build truth remains:

```txt
.gwn source -> Bash raw builder -> .gwo artifact
```

No current `.grw` source is compiled into Grogan, GrRT16, or any boot artifact.

## Relationship To Status Documents

The status wording and current layer boundaries are defined by:

```txt
docs/00-naming.md
docs/01-ecosystem-map.md
docs/13-abi-stability-gate.md
docs/18-profile-registry.md
```

This document narrows the Grogan boundary. It does not override those documents.

## Non-Goals

This seed does not add:

- a Grogan kernel implementation,
- a new boot stage,
- a new runtime service,
- a GrCall dispatch rewrite,
- interrupt or exception management,
- memory allocation,
- paging,
- protected mode,
- long mode,
- UEFI loading,
- `x86_64` execution,
- process, task, or thread management,
- filesystem services,
- driver model,
- executable `.gwo` loader,
- `.grw` parser,
- `.grw` compiler,
- `.grw` interpreter,
- hosted-native executable output,
- a profile version bump,
- a GrOS boot banner change.
