# GrABI Generated-Code Compatibility Contract

This document locks the first generated-code compatibility surface for the
current real16 profile. It defines an expected-only fixture target. It does not
add a `.grw` parser, compiler, executable loader, new GrSCall selector, or
boot-banner change.

## Compatibility Identity

```txt
grabi.real16.call.v1
profile: gros.x86.bios.real16.stage2.v0
```

The contract applies to direct near calls inside a payload loaded at
`0000:8000`. It is a machine-code ABI contract, not proof that current tooling
generates that machine code from `.grw`.

## Entry And Call Rules

- `DF` is clear at generated entry and at generated function return.
- Arguments 0 through 3 are passed in `AX`, `BX`, `CX`, and `DX`.
- Additional arguments are pushed as 16-bit words from right to left.
- The caller removes stack arguments after a direct near call.
- `AX` is the 16-bit primary return register.
- `SI`, `DI`, `BP`, `DS`, and `ES` are callee-saved.
- The callee restores `SP` to its value at function entry before `ret`.

`SS` remains callee-saved by rule; ordinary generated functions in this profile
must not modify it. There is no far-call, variadic-call, floating-point,
allocator, relocation, exception, or unwind ABI in v1.

## Expected-Only Fixture

The compatibility fixture is:

```txt
fixtures/generated-code/abi-call-preserve/
```

Its informational source declares a direct five-argument call. Its handwritten
`expected.gwn` loads the first four argument registers, pushes the fifth word,
calls a near callee, and cleans the stack argument. The callee deliberately
changes `SI`, `DI`, `DS`, and `ES`, restores them, returns the stack argument
in `AX`, clears `DF`, and returns through `ret`.

The fixture is validated by:

```txt
scripts/check_grabi_generated_code.sh
scripts/test_grabi_generated_code_failures.sh
```

These are static byte-level checks plus existing `.gwn` to `.gwo` parity. They
do not execute a generated payload and do not claim compiler output.

## Gate Status

```txt
generated-code calling compatibility: locked for grabi.real16.call.v1
.grw compiler implementation: only minimal-main subset is implemented
headered executable loading: closed
```

The ABI contract is stable enough for expected generated-code fixtures to name
this calling surface. General compiler work, including call ABI emission,
remains blocked by parser/type-checking implementation and broader emitted-code
provenance. The separate minimal-main subset is documented in
`docs/28-minimal-main-compiler-subset.md`.

## Non-Goals

This contract does not define a complete standard library, a process ABI,
runtime allocation, GrSCall expansion, payload execution, or hosted-native
calling conventions.
