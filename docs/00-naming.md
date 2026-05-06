# Naming

This document defines the public naming model for the GrOS repository. It is a
status and terminology contract only. It does not add a parser, compiler,
interpreter, linker, allocator, executable loader, kernel implementation, hosted
output, or boot banner change.

## Status Words

Project documents use these status words:

```txt
implemented      present in this repository and validated
seed/spec        specified as an initial contract, not complete implementation
reserved/future  named as a direction, not claimed as working
```

Do not describe a layer as implemented unless it has source, artifacts where
needed, and local validation.

## Core Names

`Gr`:

```txt
The broad ecosystem name.
```

Status:

```txt
seed/spec
```

`GrOS`:

```txt
The operating-system product and development workspace for the Gr ecosystem.
```

Status:

```txt
implemented seed
```

`GrBoot`:

```txt
The boot chain and bootloader layer.
```

Current implemented parts:

```txt
512-byte GrOS v0.5 BIOS boot sector
stage-1 BIOS loader for the stage-2 image
```

The current GrBoot boot chain status is defined in:

```txt
docs/21-grboot-boot-chain-status.md
```

`GrRT16`:

```txt
The current real-mode 16-bit stage-2 runtime seed.
```

Current role:

```txt
prompt loop
runtime service gate seed
real16 ABI and memory validation target
```

The current GrRT16 runtime status is defined in:

```txt
docs/20-grrt16-runtime-status.md
```

`GrABI`:

```txt
Machine, profile, handoff, calling, and memory contracts.
```

Current status:

```txt
seed/spec with static validation fixtures
```

The current GrABI contract status is defined in:

```txt
docs/22-grabi-contract-status.md
```

`GrSCall`:

```txt
Gr System Call.
```

Current implemented seed:

```txt
int 30h
```

Public naming rule:

```txt
Canonical name: GrSCall
Namespace/path: grscall
Deprecated alias: GrCall
```

Status boundary:

```txt
Current GrSCall is the runtime service gate seed through int 30h.
It is not a complete OS syscall ABI yet.
It becomes the stable Grogan syscall/service ABI only after the kernel boundary,
dispatcher ownership, object/handle model, permission model, and userspace
contract exist.
```

`Grown`:

```txt
The future native low-level systems language for GrOS.
```

Current status:

```txt
seed/spec only
```

`Grogan`:

```txt
The reserved name for the future GrOS kernel proper.
```

Current status:

```txt
reserved/future
```

The current stage-2 runtime is GrRT16. It is not Grogan proper.

The seed boundary for this reserved name is defined in:

```txt
docs/19-grogan-kernel-seed.md
```

## File Extensions

`.grw`:

```txt
Ground Readable Weave
```

Role:

```txt
Readable Grown source form.
```

Current status:

```txt
seed/spec only
```

`.gwo`:

```txt
Grown Object
```

Role:

```txt
Compiled/output artifact form.
```

Current status:

```txt
implemented as raw boot and stage artifacts
headered executable form reserved/future
```

The current `.gwo` artifact status is defined in:

```txt
docs/23-gwo-artifact-status.md
```

`.gwn`:

```txt
Ground/Woven Native
```

Role:

```txt
Low-level native/backend source layer.
```

Current status:

```txt
implemented for raw boot and stage source
```

## Correct Positioning

Use:

```txt
GrBoot loads GrRT16 today.
GrRT16 exposes the first GrSCall seed through int 30h.
Grogan is reserved as the future GrOS kernel proper.
Grown .grw is specified but not compiled yet.
Current .gwo artifacts are raw profile artifacts.
```

Avoid:

```txt
Do not describe GrOS as having a complete kernel.
Do not describe Grogan as implemented.
Do not describe Grown as compiling .grw to .gwo.
Do not describe current .gwo artifacts as full executable objects.
Do not describe GrSCall as a complete syscall ABI.
```

The current implementation readiness gate is defined in:

```txt
docs/24-implementation-readiness-status.md
```

## Versioning

The current public baseline remains:

```txt
GrOS v0.5
```

Documentation, fixture, validation, naming, or policy changes do not require a
boot banner version bump.
