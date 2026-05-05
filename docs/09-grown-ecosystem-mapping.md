# Grown Hosted-Native Ecosystem Mapping

This document defines how `.gn`, `.gr`, and `.gro` map inside the GrOS ecosystem and how hosted-native profiles can carry that ecosystem onto other operating systems. It is specification only. It does not add a compiler, parser, interpreter, runtime, standard library, build step, output artifact, or boot banner change.

## Core Model

Grown `.gn` is the unified native low-level systems language for the GrOS ecosystem. It can target GrOS-native profiles first and future hosted-native compatibility profiles later.

`.gr` is the ground layer. It is the low-level source/backend boundary that lets Grown reach the machine, kernel ABI, syscall surface, executable format, firmware entry, or GrOS profile directly.

`.gro` is the canonical grown artifact for GrOS-native outputs.

## File Roles

```txt
.gn   unified Grown source, native to the GrOS ecosystem and usable by hosted-native profiles
.gr   ground/root/raw low-level source and backend layer
.gro  grown output artifact for the GrOS ecosystem
```

## Build Mapping

Current implemented path:

```txt
.gr source -> scripts/grraw.sh -> .gro artifact
```

Reserved native GrOS path:

```txt
.gn source -> future Grown toolchain -> .gr ground layer -> .gro artifact
```

Reserved hosted-native path:

```txt
.gn source -> future Grown toolchain -> .gr host profile layer -> native host executable
```

The hosted-native path exists so GrOS ecosystem programs can be experienced on another OS while still carrying Grown semantics and the `.gr` ground layer. The host executable is native to the host operating system, but the ecosystem model remains GrOS-shaped.

## Target Profiles

Current concrete implementation:

```txt
gros.x86.bios.real16.stage2.v0
```

This profile is currently backed by the existing `x86.bios.real16.stage2.v0` handoff contract. It is 16-bit BIOS real mode, not `x86_64`.

Future GrOS-native profiles may include:

```txt
gros.x86_64.uefi.v0
gros.aarch64.uefi.v0
gros.riscv64.machine.v0
```

Future hosted-native compatibility profiles may include:

```txt
host.linux.x86_64.v0
host.windows.x86_64.v0
host.darwin.aarch64.v0
```

Hosted-native profiles are adoption and compatibility profiles. They are not the final destination of the ecosystem.

## Public Source Shape

Native GrOS profile:

```gn
target "gros.x86.bios.real16.stage2.v0"

fn main() -> void {
    return;
}
```

Hosted-native profile:

```gn
target "host.linux.x86_64.v0"

fn main() -> i32 {
    return 0;
}
```

Raw ground boundary:

```gn
raw gr("host.linux.x86_64.v0") {
    // profile-specific low-level body
}
```

The `raw gr(...)` boundary is always profile-specific. Code inside it is not portable unless another profile explicitly defines the same ground behavior.

## Non-Goals

This spec does not add:

- a `.gn` compiler
- a `.gn` interpreter
- a `.gn` parser
- generated `.gro` output from `.gn`
- hosted-native executable output
- a standard library
- a language version bump
- a GrOS boot banner change
