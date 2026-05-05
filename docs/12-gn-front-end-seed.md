# Grown `.gn` Front-End Seed

This document defines the first source front-end seed for Grown `.gn`. It is specification only. It does not add a parser, compiler, interpreter, type checker, code generator, standard library, hosted-native executable output, or boot banner change.

## Scope

The front-end seed describes the source forms that future tooling must recognize before lowering Grown into a `.gr` ground layer or another profile-specific backend.

The seed covers:

- source bytes
- comments
- identifiers
- literals
- target declaration
- function declaration
- return statement
- raw `.gr` boundary

Everything else remains reserved.

## Source Bytes

`.gn` source is text. The seed requires ASCII-compatible source bytes.

Allowed line endings:

```txt
LF
CRLF
```

Tooling must normalize line endings before parsing tokens.

Tabs and spaces are both whitespace. Formatting is not semantic in this seed.

## Comments

Line comments:

```gn
// comment
```

Block comments are reserved and not part of the seed:

```gn
/* reserved */
```

## Identifiers

Identifier seed:

```txt
[A-Za-z_][A-Za-z0-9_]*
```

Identifiers are case-sensitive.

Reserved words:

```txt
target
fn
return
raw
gr
void
bool
u8
u16
u32
i8
i16
i32
```

## Literals

String literal seed:

```gn
"text"
```

String literals are currently used for profile names only. Escape rules are reserved.

Integer literal seed:

```gn
0
123
0x7c00
```

Integer type inference is reserved. A future type checker must validate whether a literal fits the target type.

Boolean literals are reserved.

## Target Declaration

A `.gn` source file must begin with one target declaration:

```gn
target "gros.x86.bios.real16.stage2.v0"
```

The target string selects a profile. The seed does not allow multiple target declarations in one source file.

## Function Declaration

Function declaration seed:

```gn
fn main() -> void {
    return;
}
```

Rules:

- `fn` introduces a function.
- The seed only reserves zero-argument functions.
- The return type is required.
- Function bodies use braces.
- Nested functions are not specified.

The first logical entrypoint remains:

```gn
fn main() -> void
```

Profile-specific tooling may map `main` to a different physical entrypoint.

## Return Statement

Void return:

```gn
return;
```

Value return:

```gn
return 0;
```

The seed does not define expression precedence. A return value may only be a literal until expressions are specified.

## Raw `.gr` Boundary

Raw ground boundary seed:

```gn
raw gr("gros.x86.bios.real16.stage2.v0") {
    // profile-specific low-level body
}
```

Rules:

- `raw gr(...)` is profile-specific.
- Code inside the block is not portable by default.
- The block body is reserved for future `.gr` embedding rules.
- Tooling must reject a raw block whose profile string is incompatible with the file target unless a future spec explicitly permits cross-profile raw blocks.

## Minimal Source Examples

Native GrOS stage-2 profile:

```gn
target "gros.x86.bios.real16.stage2.v0"

fn main() -> void {
    return;
}
```

Hosted-native compatibility profile:

```gn
target "host.linux.x86_64.v0"

fn main() -> i32 {
    return 0;
}
```

## Reserved Syntax

The following are reserved:

- imports
- modules
- namespaces
- constants
- variables
- assignments
- arithmetic expressions
- pointers
- arrays
- structs
- enums
- traits or interfaces
- generics
- macros
- attributes
- inline assembly
- error handling
- heap allocation

## Non-Goals

This seed does not add:

- executable `.gn` tooling
- parsing in the current Bash build flow
- `.gn` to `.gr` lowering
- `.gn` to `.gro` output
- hosted-native executable output
- a standard library
- a language version bump
- a GrOS boot banner change
