# `.gwo` Payload Header Seed

This document defines the first reserved header shape for future executable `.gwo` payloads. It is a seed specification only. It does not change the current boot images, add a loader implementation, add a `.grw` compiler, add a linker, add relocations, or change the GrOS boot banner.

## Current State

Current committed `.gwo` artifacts remain raw boot images:

```txt
dist/gros-v0.5.gwo
dist/gros-stage2.gwo
```

They are headerless by design.

The stage-2 image remains:

```txt
LBA 0     512-byte stage-1 BIOS loader
LBA 1..4  2048-byte raw stage-2 payload
```

Stage-1 still loads stage-2 to:

```txt
0000:8000
```

## Header Goal

The future `.gwo` header exists to let GrOS identify executable payloads before running them. It should describe enough metadata for a loader or runtime to reject incompatible payloads before control transfer.

The header is not required for boot sectors or the current stage-2 raw payload.

## Loading Boundary

There are two `.gwo` classes in the seed model:

```txt
raw-profile .gwo
headered-executable .gwo
```

`raw-profile .gwo`:

```txt
Current bootable images whose layout is defined by a profile-specific boot or
handoff contract outside a `.gwo` header.
```

Current raw-profile examples:

```txt
dist/gros-v0.5.gwo
dist/gros-stage2.gwo
```

`headered-executable .gwo`:

```txt
Future payload images that begin with the reserved `.gwo` header and require a
header-aware loader before execution.
```

The current stage-1 loader is a raw-profile loader only. It must continue to
load the stage-2 payload by sector layout and fixed handoff contract:

```txt
LBA 1..4 -> 0000:8000
```

It must not be described as a header-aware `.gwo` executable loader.

## Loader Decision Seed

A future header-aware loader must classify a candidate payload before control
transfer:

```txt
1. Read enough bytes to inspect the seed magic.
2. If the magic is absent, either reject the payload or dispatch to an explicitly
   selected raw-profile loader.
3. If the magic is present, validate every supported header field before using
   the entrypoint.
4. Reject unsupported header size, version, profile, flags, size, checksum, or
   nonzero reserved bytes.
5. Reject any entry offset outside the declared payload.
6. Transfer control only after the payload class and profile are accepted.
```

This decision seed prevents silent fallback from a malformed headered payload
into raw execution.

## Current Raw Profile Rule

The current raw boot artifacts are valid only because their profile contracts
define their layout:

```txt
gros-v0.5.gwo       raw 512-byte BIOS boot sector
gros-stage2.gwo     raw 512-byte stage-1 plus 2048-byte stage-2 payload
```

They do not carry:

```txt
header magic
profile_id
entry_offset
payload_size
payload_checksum
```

Any future tooling that wants to inspect these files must treat them as raw
profile artifacts, not as failed headered executables.

## Future Header Layout

All integer fields are little-endian.

```txt
offset  size  field
00h     4     magic
04h     2     header_size
06h     2     header_version
08h     4     profile_id
0Ch     2     flags
0Eh     2     entry_offset
10h     4     payload_size
14h     4     payload_checksum
18h     8     reserved
```

Minimum seed header size:

```txt
32 bytes
```

## Field Seed

`magic`:

```txt
47 52 4F 00
```

ASCII meaning:

```txt
GRO\0
```

`header_size`:

```txt
0020h for the seed layout
```

`header_version`:

```txt
0000h for the seed layout
```

`profile_id`:

Reserved profile compatibility marker. The exact numeric mapping is not assigned yet.

Initial reserved profile names:

```txt
gros.x86.bios.real16.stage2.v0
gros.x86_64.uefi.v0
host.linux.x86_64.v0
host.windows.x86_64.v0
host.darwin.aarch64.v0
```

`flags`:

Reserved bitset. Unknown flags must make a loader reject the payload.

`entry_offset`:

Offset from the first payload byte after the header to the entrypoint. For the current real16 profile, a future loader may combine this with a profile load address.

`payload_size`:

Payload byte count after the header. The header itself is not included.

`payload_checksum`:

Reserved integrity field. Algorithm is not assigned yet. A value of `00000000h` means no checksum is declared for the seed.

`reserved`:

Must be zero in the seed layout.

## Compatibility Rules

- Current raw `.gwo` boot images do not carry this header.
- A loader must not assume all `.gwo` files are headered.
- A header-aware loader must first check `magic`.
- If `magic` is absent, handling is profile-specific and may fall back to raw boot image behavior.
- If `magic` is present but `header_size`, `header_version`, profile, flags, size, or checksum are unsupported, the loader must reject the payload.
- Headered payloads must not be accepted by the current stage-1 loader until a future stage explicitly implements that behavior.
- A malformed headered payload must not fall back to raw execution.
- Header-aware execution requires an explicit accepted profile match.
- Unknown flags and nonzero reserved bytes are rejection conditions in the seed.

## Relationship To Grown

Future Grown `.grw` compilation may target:

```txt
.grw source -> .gwn ground layer -> headered .gwo payload
```

That path is not implemented. This seed only reserves the artifact metadata shape needed by a future loader and toolchain.

## Non-Goals

This seed does not add:

- a header to existing `.gwo` artifacts
- a `.grw` compiler
- a linker
- relocation records
- symbol tables
- imported service tables
- a header classifier implementation
- executable loading in stage-2
- protected mode or long mode
- a boot banner change
