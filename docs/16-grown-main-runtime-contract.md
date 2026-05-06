# Grown Main Runtime Contract Seed

This document defines the first runtime contract seed for a minimal Grown
`fn main()` under the current GrOS stage-2 profile. It is specification only. It
does not add a parser, compiler, interpreter, linker, code generator, allocator,
hosted-native executable output, executable `.gwo` loader, or boot banner change.

## Scope

Current profile:

```txt
gros.x86.bios.real16.stage2.v0
```

Current machine environment:

```txt
x86 BIOS real mode
stage-2 payload loaded at 0000:8000
2048-byte raw payload reservation
```

This contract covers only the smallest future Grown source shape:

```grw
target "gros.x86.bios.real16.stage2.v0"

fn main() -> void {
    return;
}
```

## Logical Entry

The logical Grown entrypoint is:

```txt
main
```

The current profile maps that logical entry to the physical stage-2 payload
entrypoint:

```txt
CS:IP = 0000:8000
```

Future profiles may place a small profile entry stub before `main`. The current
seed fixture does not require such a stub.

## Entry State

The stage-1 to stage-2 handoff defines the physical entry state. The relevant
seed state for a minimal `main` is:

```txt
CS:IP = 0000:8000
SS:SP = 0000:7C00
DF clear
```

The minimal `main` contract must not depend on unspecified BIOS register values.
Any future generated entry sequence must initialize registers before relying on
them.

## Return Behavior

Returning from the current bare-metal stage-2 entrypoint is undefined. There is
no caller above the stage-2 payload.

For the expected-only minimal fixture, this source behavior:

```grw
fn main() -> void {
    return;
}
```

may be represented by a low-level halt loop:

```txt
cli
hlt
jmp self
```

In current raw bytes, the seed representation is:

```txt
FA F4 EB FC
```

This is a fixture contract only. It is not compiler output.

## Data Requirements

The minimal `fn main() -> void` seed requires no heap, globals, string literals,
stack arguments, or runtime service calls.

Required memory behavior:

- code lives inside the stage-2 payload image
- no data outside the payload image is read
- no stack storage is required beyond the inherited valid stack
- no heap or allocator is required

This keeps the first generated-code fixture independent of console output,
string storage, or service selector availability.

## Runtime Service Requirements

The minimal `main` contract does not require `int 30h`.

The runtime gate still exists for richer future Grown programs, but this seed
does not depend on:

- `runtime/control.probe`
- `console/text.write_cstr`
- `console/text.write_char`

That separation matters because the first `main` fixture should prove entry and
return behavior before proving runtime I/O.

## Fixture Relationship

The first expected-only fixture is:

```txt
fixtures/generated-code/minimal-main-void/
```

Its manifest records:

```txt
expected_size=2048
entry_address=0000:8000
status=expected-only
```

Its handwritten `.gwn` source remains the expected low-level representation for a
future compiler target. The repository must not claim that current tooling
compiled `source.grw` into `expected.gwn` or `expected.gwo`.

## Gate Status

This contract helps narrow the ABI stability gate, but it does not open it.

Still missing before `.grw` lowering can start:

- parser rules implemented in tooling
- type checking rules implemented in tooling
- generated `.gwn` emission
- generated `.gwo` parity against fixtures
- payload format decision for executable generated artifacts

Until those exist, Grown work remains specification and expected-fixture work.

## Non-Goals

This seed does not define:

- command-line arguments
- environment blocks
- process exit status
- hosted-native `main`
- panic behavior
- exceptions or unwinding
- stack frames
- function calls
- static initialization
- allocator behavior
- system calls
- executable `.gwo` loading
- a version bump
