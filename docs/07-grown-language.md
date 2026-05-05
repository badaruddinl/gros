# Grown Language Spec

Grown is the planned native low-level systems language for GrOS. It belongs to the Gr ecosystem, but its primary semantic target is GrOS: kernels, loaders, drivers, runtime services, ABI/profile-aware libraries, hosted-native compatibility layers, and device/profile-specific payloads.

Its source extension is:

```txt
.gn
```

This document is a seed specification only. It does not implement a compiler, interpreter, parser, runtime, standard library, or build step.

## Naming

```txt
Grown  native low-level GrOS systems language
.gn    unified Grown source
.gr    ground/root/raw source and low-level backend layer
.gro   grown output artifact
```

The name is **Grown**.

## File Roles

`.gr` remains the source of truth for the current boot and stage code:

- raw boot bytes
- low-level loader source
- early kernel/runtime source
- validation-friendly machine-level source

`.gn` is unified Grown source:

- structured systems code above raw boot source
- GrOS kernel, driver, runtime, and ABI/profile-aware source
- hosted-native compatibility source for future host profiles
- code that can be lowered through `.gr` into a `.gro` artifact or a hosted-native executable

`.gro` remains the canonical GrOS ecosystem artifact:

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
target "gros.x86.bios.real16.stage2.v0"

fn main() -> void {
    return;
}
```

Hosted-native compatibility profiles use the same source language shape:

```gn
target "host.linux.x86_64.v0"

fn main() -> i32 {
    return 0;
}
```

Raw ground boundaries are profile-specific:

```gn
raw gr("host.linux.x86_64.v0") {
    // profile-specific low-level body
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

## Output Profiles

In this spec, target means a GrOS execution profile, device/profile contract, or hosted-native compatibility profile. Windows, Linux, macOS, and Android are not GrOS replacements; future hosted-native profiles may use them as adoption surfaces where Grown programs run as native host executables while keeping GrOS language and ground-layer semantics.

Future Grown output profiles may include:

- raw GrOS stage payload `.gro`
- GrOS kernel `.gro`
- GrOS executable `.gro`
- GrOS library/package `.gro`
- hosted-native Linux executable
- hosted-native Windows executable
- hosted-native Darwin executable

The current concrete build path remains:

```txt
.gr source -> Bash raw builder -> .gro artifact
```

No `.gn` source is part of the active build yet.

## ABI Dependency

Complete native `.gn` code generation and runtime mapping await enough GrOS ABI surface for generated code.

The minimum required contracts are:

- function calling convention
- register preservation rules
- stack frame rules
- memory model
- syscall or kernel service interface
- object/executable `.gro` layout
- panic or halt behavior

The existing `x86.bios.real16.stage2.v0` handoff profile is a machine-level payload entry contract. It is necessary, but not sufficient, for a full Grown language runtime mapping.

## Non-Goals

This seed spec does not add:

- a `.gn` compiler
- a `.gn` interpreter
- a `.gn` parser
- generated `.gro` output from `.gn`
- hosted-native executable output
- a standard library
- a language version bump
- a GrOS boot banner change
