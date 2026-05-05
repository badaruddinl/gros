# ABI Stability Gate

This document defines the minimum stability gate before implementing `.gn` lowering, a Grown compiler, or executable `.gro` payload loading. It is a technical checkpoint, not a roadmap. It does not add a compiler, parser, linker, loader, executable format implementation, hosted-native output, or boot banner change.

## Purpose

Grown `.gn` code generation must not start while the stage-2 ABI is still easy to break. This gate defines what must be stable enough before generated code depends on it.

The current implementation remains:

```txt
gros.x86.bios.real16.stage2.v0
```

This is still x86 BIOS real mode, not `x86_64`.

## Gate Status

Current status:

```txt
not stable for `.gn` compiler implementation
```

Reason:

- runtime services are minimal
- memory model is not specified
- payload loading is not implemented
- headered `.gro` execution is not implemented
- no generated-code fixture exists

## Required Stable Contracts

The following contracts must be stable before `.gn` lowering starts.

## 1. Entrypoint Contract

Required:

- profile name
- physical load address
- physical entrypoint
- segment register state
- interrupt state
- direction flag state
- stack start
- return behavior

Current seed:

```txt
CS:IP = 0000:8000
SS:SP = 0000:7C00
DF clear
```

Status:

```txt
partially stable
```

## 2. Function Calling Convention

Required:

- argument registers
- return registers
- caller-saved registers
- callee-saved registers
- stack argument order
- stack cleanup owner

Current seed:

```txt
AX BX CX DX arguments 0..3
AX primary return value
DX:AX optional 32-bit return value
caller-saved AX BX CX DX FLAGS
callee-saved SI DI BP SP DS ES SS
```

Status:

```txt
seeded, not proven by generated code
```

## 3. Runtime Service Gate

Required:

- interrupt or call gate
- selector layout
- argument registers
- success return convention
- error return convention
- unsupported selector behavior
- register preservation per service

Current gate:

```txt
int 30h
AH service group
AL service id
CF=0 success
CF=1 error
AX result or error code
```

Implemented services:

```txt
00h:00h runtime/control.probe
01h:00h console/text.write_cstr
01h:01h console/text.write_char
```

Status:

```txt
usable seed, not enough for general `.gn` runtime
```

## 4. Memory Model

Required:

- address width
- pointer representation
- valid memory ranges
- code/data separation rules
- static data rules
- stack collision rules
- heap or no-heap rule

Current seed:

```txt
docs/14-real16-memory-model.md
```

Status:

```txt
seeded with static memory and near-pointer fixtures, not proven by generated code
```

This blocks pointer types, arrays, strings, global data, and most useful generated `.gn` code.

## 5. Payload Format

Required:

- raw versus headered payload decision
- header detection rules
- entry offset rules
- payload size rules
- checksum behavior
- rejection behavior

Current status:

```txt
header seed reserved, loader not implemented
```

The future header shape is reserved in:

```txt
docs/11-gro-payload-header.md
```

## 6. Validation Requirements

Required before `.gn` lowering starts:

- raw boot validation remains green
- stage-2 handoff validation remains green
- runtime ABI byte fixture remains green
- at least one generated-code fixture exists
- generated-code fixture does not require hosted languages in the build path

Current status:

```txt
manual `.gr` runtime fixtures only
```

## Allowed Before Gate Completion

Allowed:

- improve `.gr` stage-2 runtime services
- improve Bash validation
- add technical specs
- add static fixtures over `.gro` bytes
- add QEMU smoke coverage

Not allowed yet:

- implement `.gn` parser
- implement `.gn` compiler
- implement `.gn` interpreter
- claim generated `.gro` output from `.gn`
- claim hosted-native executable output

## Opening The Gate

The gate may open when all of these are true:

- runtime service selectors needed by a minimal `.gn` program are assigned
- return and error conventions are validated
- memory model seed is specified
- payload format decision for generated code is specified
- at least one generated-code fixture can be validated without adding high-level build dependencies
- current `make validate` and QEMU smoke remain green locally

Until then, `.gn` work stays in specification and compatibility planning.
