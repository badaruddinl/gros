# Self-Hosting Alpha GWO2 and Grown Contract

This contract opens Batch 1.4. GWO2 is the executable form used by the first
real Grown compiler. GWO1 remains a compatibility seed and is not promoted by
this document.

## GWO2 container

Every field is little-endian. The fixed header is 32 bytes:

```txt
magic              4 bytes: "GWO2"
version            u16: 2
header_size        u16: 32
flags              u32: zero in Alpha
target_id          u32: gros.x86.bios.longmode.grogan.v1
kind               u16: 1 bytecode, 2 native-reserved
section_count      u16: 1..16
entry_section      u16
entry_offset       u32
total_size         u32
header_checksum    u32
```

Each section descriptor is 24 bytes: kind, permissions, file offset, file
size, virtual size, and checksum. Section offsets and sizes must be aligned,
non-overlapping, within `total_size`, and below the image resource limit. The
loader verifies every checksum and the bytecode verifier runs before a process
is created.

## Alpha bytecode

Bytecode is a deterministic stack machine. The initial instruction families
are:

```txt
const_i64  load_local  store_local  add_i64  sub_i64  mul_i64  div_i64
eq_i64     lt_i64      jump         jump_if_false
call       return      load_bytes   store_bytes  syscall  halt
```

Each instruction has a fixed encoding and declared stack effect. Jumps target
instruction boundaries. Locals, call depth, byte arrays, and instruction count
are bounded and checked before execution. Invalid bytecode is rejected before
any user memory or syscall side effect occurs.

## Grown Alpha source

The self-hostable subset includes modules, typed functions, locals, assignment,
`if/else`, `while`, integers, booleans, bytes, strings, byte arrays, and the
console/file standard library. Source diagnostics carry file, line, column,
and a stable error code. Imports are repository-relative and resolved from a
canonical module manifest; ambient host paths are not allowed.

## Bootstrap stages

```txt
grc0 (hosted reference compiler) -> GWO2 bytecode
grc0 compiles grc1 written in Grown
GrOS GrVM runs grc1.gwo
grc1 compiles its own source inside GrOS
```

`grc0` and `grc1` must agree on canonical module order, diagnostics, symbol
IDs, and emitted bytes. A native backend is reserved for after Alpha; bytecode
self-hosting is not a fixture or a hardcoded payload shortcut.

## Batch 1.4 gate

Fixtures must accept a valid multi-function bytecode module and reject bad
magic/version, section overlap, checksum mismatch, invalid entry, stack-effect
underflow, non-boundary jumps, unknown opcodes, and unresolved imports.
