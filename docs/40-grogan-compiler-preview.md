# Grogan Compiler Preview

Phase 8 opens a useful, intentionally small Grown compiler slice for the
Grogan x86_64 profile. It is a real source-to-artifact path, not a fixture
label or a hardcoded kernel payload.

## Accepted source

The compiler accepts one grammar production:

```grw
target "gros.x86.bios.longmode.grogan.v0"
fn main() -> void {
    grogan::write();
    grogan::exit();
}
```

LF/CRLF input and `//` line comments are normalized. Unknown targets,
functions, or stdlib calls are rejected.

## Lowering

`grogan::write()` and `grogan::exit()` lower to the two phase-7 syscall
selectors. The compiler computes the payload length and byte-sum checksum,
then emits a 41-byte GWO1 artifact. `scripts/build_longmode_image.sh`
regenerates that artifact and embeds it with `incbin` into the x86_64 image,
so the QEMU proof executes compiler-produced bytes.

## Gates

```bash
make grogan-compiler
make grogan-compiler-failures
make grogan-shell-qemu
```

This preview does not claim a general parser, type checker, optimizer, linker,
relocations, dynamic allocation, strings, or a broad standard library.
