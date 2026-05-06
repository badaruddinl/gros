# Grown Hosted-Native Ecosystem Mapping

This document defines how `.grw`, `.gwn`, and `.gwo` map inside the GrOS ecosystem and how hosted-native profiles can carry that ecosystem onto other operating systems. It is specification only. It does not add a compiler, parser, interpreter, runtime, standard library, build step, output artifact, or boot banner change.

## Core Model

Grown `.grw` is Ground Readable Weave, the main native low-level systems language source form for the GrOS ecosystem. It can target GrOS-native profiles first and future hosted-native compatibility profiles later.

`.gwn` is Ground/Woven Native. It is the low-level source/backend boundary that lets Grown reach the machine, kernel ABI, syscall surface, executable format, firmware entry, or GrOS profile directly.

`.gwo` is Grown Object, the canonical artifact form for GrOS-native outputs.

## File Roles

```txt
.grw   Ground Readable Weave, the main Grown source form
.gwo   Grown Object, the compiled/output artifact form
.gwn   Ground/Woven Native, the low-level native/backend layer
```

## Build Mapping

Current implemented path:

```txt
.gwn source -> scripts/gwnraw.sh -> .gwo artifact
```

Reserved native GrOS path:

```txt
.grw source -> future Grown toolchain -> .gwn ground layer -> .gwo artifact
```

Reserved hosted-native path:

```txt
.grw source -> future Grown toolchain -> .gwn host profile layer -> native host executable
```

The hosted-native path exists so GrOS ecosystem programs can be experienced on another OS while still carrying Grown semantics and the `.gwn` ground layer. The host executable is native to the host operating system, but the ecosystem model remains GrOS-shaped.

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

The canonical profile status registry is:

```txt
docs/18-profile-registry.md
```

## Public Source Shape

Native GrOS profile:

```grw
target "gros.x86.bios.real16.stage2.v0"

fn main() -> void {
    return;
}
```

Hosted-native profile:

```grw
target "host.linux.x86_64.v0"

fn main() -> i32 {
    return 0;
}
```

Raw ground boundary:

```grw
raw gwn("host.linux.x86_64.v0") {
    // profile-specific low-level body
}
```

The `raw gwn(...)` boundary is always profile-specific. Code inside it is not portable unless another profile explicitly defines the same ground behavior.

## Non-Goals

This spec does not add:

- a `.grw` compiler
- a `.grw` interpreter
- a `.grw` parser
- generated `.gwo` output from `.grw`
- hosted-native executable output
- a standard library
- a language version bump
- a GrOS boot banner change
