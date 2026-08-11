# Self-Hosting Alpha GWO2 and Grown Contract

This contract opens Batch 1.4. GWO2 is the executable form used by the first
real Grown compiler. GWO1 remains a compatibility seed and is not promoted by
this document.

## GWO2 container

Every field is little-endian. The fixed header is 32 bytes. The Alpha v2
encoding below is canonical; no field is inferred from a host compiler ABI:

```txt
offset  size  field
0       4     magic: "GWO2"
4       2     version: 2
6       2     target_id: 1 (gros.x86.bios.longmode.grogan.v1)
8       2     kind: 1 (bytecode; 2 is reserved for native)
10      2     reserved: zero
12      4     header_size: 32
16      4     section_count: 1..16
20      4     entry_offset: byte offset in the bytecode section
24      4     code_size: bytecode section size
28      4     image_checksum: FNV-1a over the section table and section bytes
```

The Alpha bytecode section table has 16-byte descriptors:

```txt
kind      u32: 1 (bytecode)
offset    u32: file offset of bytes
size      u32: byte count (must equal code_size for the one-section Alpha)
checksum  u32: FNV-1a over the section bytes
```

The table and section must be within the image, non-overlapping, and below the
1 MiB image limit. The loader verifies both checksums and the bytecode verifier
runs before a process is created. Alpha v2 currently permits exactly one
bytecode section; extra section kinds are reserved until the loader has a
tested permission and relocation model.

## Alpha bytecode

Bytecode is a deterministic stack machine. The first executable encoding is:

```txt
0x01 const_i32 <u32>
0x02 load_local <u8>
0x03 store_local <u8>
0x04 add_i32       0x05 sub_i32       0x06 mul_i32
0x07 div_i32       0x08 eq_i32        0x09 lt_i32
0x0a jump <i16-relative>       0x0b jump_if_zero <i16-relative>
0x0c import <u8-id> <u8-argc>   0x0d return   0x0e halt
0x0f const_bytes <u8-len> <bytes>
0x10 load_byte(pointer,index)   0x11 store_byte(pointer,index,value)
0x12 duplicate                   0x13 drop
0x14 call <u16-target> <u8-argc> <u8-result>
0x15 return_void
```

Imports are fixed and verifier-checked: id 1 is `print_i32(i32)`, id 2 is
`exit(i32)`, and id 3 is `newline()`. IDs 4-13 are the checked runtime ABI:
`console_read`, `file_open`, `file_read`, `file_write`, `file_close`,
`file_stat`, `mem_grow`, `path_create`, `file_unlink`, and `print_bytes`.
`const_bytes` copies a bounded NUL-terminated literal into the runtime's
owned byte pool; byte load/store operations validate the pointed-to user span.
Each instruction has a declared stack effect. Jumps target instruction
boundaries. Locals and the operand stack are bounded, and invalid bytecode is
rejected before any user memory or syscall side effect occurs.

## Grown Alpha source

The first executable subset has typed functions with i32-compatible parameters
and results, i32/pointer locals, assignment, `if/else`, `while`, integer and
boolean expressions, byte strings, byte load/store, memory growth, and the
console/file standard-library calls listed above. Function calls use absolute
bytecode offsets and a bounded call depth; local slots are statically bounded
per artifact. Source diagnostics carry file, line, and column. Modules,
arrays-as-a-language-type, and richer structural type checking remain explicit
follow-on work.

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

The host verifier fixtures accept the deterministic single-section image and
reject bad magic/version, section overlap or size, checksum mismatch, invalid
entry, stack-effect underflow, non-boundary jumps, unknown opcodes, and
unresolved imports. Multi-function modules are a later loader milestone, not a
fixture claim for this first compiler slice.
