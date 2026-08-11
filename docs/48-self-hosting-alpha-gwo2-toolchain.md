# Self-Hosting Alpha GWO2 Toolchain

This checkpoint turns the GWO2 and Grown contracts into a tested hosted
reference path. It is intentionally a compiler and VM, not a pattern matcher:
the lexer, parser, expression lowering, deterministic bytecode emitter, image
checksums, verifier, and stack VM all participate in the result.

## Implemented path

```txt
examples/grown-alpha/hello.grw
        │
        ▼
scripts/grc0.sh (tools/grc0.c)
        │  canonical GWO2 bytes
        ▼
scripts/grvm.sh (tools/grvm.c)
        │
        ▼
deterministic console output
```

`grc0` accepts the Alpha target declaration, one typed `fn main`, i32/pointer
locals, assignment, integer expressions, `if/else`, `while`, byte literals,
byte load/store, memory growth, and the checked console/file imports. It emits
the GWO2 v2 single-bytecode-section image from docs/45. `grvm` verifies the
image before executing it with bounded literals, locals, operand stack, VM
memory, file handles, and instruction steps.

## Evidence and failure handling

```bash
make gwo2-host
make gwo2-host-failures
```

The positive gate compiles the same source twice, requires byte-for-byte
identity, and executes it to produce `28`. The negative gate creates validly
checksummed malformed images and proves rejection of bad container fields,
overlap/size errors, invalid entries, unknown instructions, stack underflow,
non-boundary jumps, and unsupported imports.

The hosted path is the reference implementation for the later in-OS GrVM. The
storage-smoke fixture proves byte round-trip and unlink through the same import
signatures. It does not yet claim a multi-module linker or compiler
self-rebuild; those are the next roadmap gates.
