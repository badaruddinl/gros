# Grown Language Seed Spec

Grown is the future higher-level language layer for the Gr ecosystem. Its source extension is:

```txt
.gn
```

This document is a seed specification only. It does not implement a compiler, interpreter, parser, runtime, standard library, or build step.

## Naming

```txt
Grown  language name
.gn    Grown source
.gr    ground/root/raw low-level source
.gro   grown output artifact
```

The name is **Grown**.

## File Roles

`.gr` remains the source of truth for the current boot and stage code:

- raw boot bytes
- low-level loader source
- early kernel/runtime source
- validation-friendly machine-level source

`.gn` is reserved for future Grown source:

- structured code above raw boot source
- code that targets a defined GrOS ABI profile
- code that can be lowered into a `.gro` artifact through a future toolchain

`.gro` remains a build artifact:

- boot image
- stage payload
- kernel image
- executable image
- library or package artifact

## Entrypoint

The first logical Grown entrypoint form is:

```gn
fn main() -> void
```

The physical entrypoint is target-defined. For the current GrOS stage-2 profile, the machine entry remains:

```txt
CS:IP = 0000:8000
```

Grown source must not depend directly on BIOS entry registers unless it explicitly targets a bare-metal profile that exposes those registers.

## Minimal Types

The first type set is intentionally small:

```txt
void
bool
u8
u16
u32
i8
i16
i32
```

Pointer types are reserved until memory and ABI rules are stable:

```gn
ptr<T>
```

Target-sized integer types are reserved until target profiles define pointer width and address rules:

```txt
usize
isize
```

## Minimal Syntax Shape

The seed syntax shape is C-like but intentionally incomplete:

```gn
fn main() -> void {
    return;
}
```

The following are not specified yet:

- modules
- imports
- structs
- enums
- traits or interfaces
- generics
- heap allocation
- strings
- inline assembly
- macros
- error handling model

## Output Targets

Future Grown output targets may include:

- raw stage payload `.gro`
- GrOS kernel `.gro`
- executable `.gro`
- library/package `.gro`

The current concrete build path remains:

```txt
.gr source -> Bash raw builder -> .gro artifact
```

No `.gn` source is part of the active build yet.

## ABI Dependency

Grown cannot become an implementation target until GrOS defines enough ABI surface for generated code.

The minimum required contracts are:

- function calling convention
- register preservation rules
- stack frame rules
- memory model
- syscall or kernel service interface
- object/executable `.gro` layout
- panic or halt behavior

The existing `x86.bios.real16.stage2.v0` handoff profile is a machine-level payload entry contract. It is necessary, but not sufficient, for a full Grown language target.

## Non-Goals

This seed spec does not add:

- a `.gn` compiler
- a `.gn` interpreter
- a `.gn` parser
- generated `.gro` output from `.gn`
- a standard library
- a language version bump
- a GrOS boot banner change
