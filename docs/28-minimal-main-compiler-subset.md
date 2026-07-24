# Minimal Grown Main Compiler Subset

This document defines the first executable Grown subset. It is intentionally
one production: it accepts exactly a target declaration for
`gros.x86.bios.real16.stage2.v0` and `fn main() -> void { return; }`.

The local Bash compiler is `scripts/grw_minimal_main.sh`. It emits deterministic
GWN at origin `8020h`, containing a halt loop and padding to the 2016-byte
payload reservation. `scripts/build_headered_payload_image.sh` combines that
payload with the existing stage-1 and fixed v1 header.

The tracked input is `examples/generated/minimal-main-void.grw`. Its build
products reside under ignored `build/generated/`; they are compiler output, not
expected-only fixtures.

Acceptance evidence is deliberately end-to-end:

- `scripts/test_grw_minimal_main_failures.sh` rejects unsupported target,
  body, extra function, and comments;
- `scripts/check_grw_minimal_main.sh` checks compiler output, header, and entry;
- `scripts/qemu_generated_minimal_main.sh` traces execution at `0000:8020`.

This does not implement a general parser, comments, declarations, expressions,
calls, type checking, ABI-call generation, or a general executable loader.
