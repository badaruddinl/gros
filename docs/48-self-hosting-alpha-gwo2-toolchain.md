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
scripts/grc0.sh (tools/grc0.rs)
        │  canonical GWO2 bytes
        ▼
scripts/grvm.sh (tools/grvm.c)
        │
        ▼
deterministic console output
```

`grc0` accepts the Alpha target declaration, typed multi-function definitions
with i32-compatible parameters/results, i32/pointer locals, assignment,
integer/boolean expressions, `if/else`, `while`, byte literals, byte
load/store, memory growth, and the checked console/file imports. It emits
the GWO2 v2 single-bytecode-section image from docs/45. `grvm` verifies the
image before executing it with bounded literals, locals, operand stack,
call frames, VM memory, file handles, and instruction steps.

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
storage-smoke and functions fixtures prove byte round-trip, unlink, and
function call/return through the same import and bytecode signatures.

The bootstrap compiler is Rust (`tools/grc0.rs`); this is a deliberate
implementation constraint for the first compiler stage. The C programs
`tools/gwo2.c` and `tools/grvm.c` remain host-only verifier/VM reference tools
and are not a compiler or a self-hosting shortcut.

The hosted self-host gate now executes the Rust-produced `grc1.gwo`, lets that
Grown compiler emit `grc2.gwo`, executes `grc2.gwo` twice, and requires the two
Grown-produced artifacts to be byte-identical:

```bash
make grogan-self-host
```

The in-OS counterpart is exercised separately by `make grogan-self-host-qemu`;
it boots a clean image, compiles the installed compiler source from the ring-3
shell, runs the result, and checks that `grc2.gwo` is persisted in GFS2.
