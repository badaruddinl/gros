# `.gwo` Payload Header Seed

This document defines the first header shape for executable `.gwo` payloads. The
fixed v1 header is implemented for the current stage-2 reservation only; it
does not add a general executable loader, `.grw` compiler, linker, or relocation.

## Current State

The committed single-sector baseline remains raw:

```txt
dist/gros-v0.5.gwo
```

`dist/gros-stage2.gwo` is a hybrid boot container:

```txt
LBA 0     512-byte stage-1 BIOS loader
LBA 1..4  32-byte fixed v1 header plus 2016-byte executable payload
```

Stage-1 still loads stage-2 to:

```txt
0000:8000
```

The full accepted field matrix and rejection contract are in
`docs/27-headered-stage2-loader-contract.md`.

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

Current raw-profile example:

```txt
dist/gros-v0.5.gwo
```

`headered-executable .gwo`:

```txt
Payload images that begin with the `.gwo` header and require a header-aware
loader before execution.
```

The current stage-1 loader recognizes the fixed current header within its
stage-2 reservation. It loads all four sectors by fixed layout:

```txt
LBA 1..4 -> 0000:8000
```

It validates the fixed v1 current-profile fields and transfers dynamically to
the declared payload entry. It is not a general `.gwo` executable loader.

The current GrBoot raw-profile loader status is summarized in:

```txt
docs/21-grboot-boot-chain-status.md
```

The current `.gwo` artifact status is summarized in:

```txt
docs/23-gwo-artifact-status.md
```

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
gros-stage2.gwo     512-byte stage-1 plus 32-byte header and 2016-byte payload
```

`gros-v0.5.gwo` does not carry:

```txt
header magic
profile_id
entry_offset
payload_size
payload_checksum
```

Tooling must treat `gros-v0.5.gwo` as raw. It must inspect the stage-2
reservation according to the fixed current loader contract, not as a generic
headered executable.

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

Profile compatibility marker. The first assigned mapping is `00000000h` for
`gros.x86.bios.real16.stage2.v0`.

Profile names and statuses are registered in:

```txt
docs/18-profile-registry.md
```

Seed profile names include:

```txt
gros.x86.bios.real16.stage2.v0
gros.x86_64.uefi.v0
gros.aarch64.uefi.v0
gros.riscv64.machine.v0
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

- `gros-v0.5.gwo` does not carry this header.
- A loader must not assume all `.gwo` files are headered.
- A header-aware loader must first check `magic`.
- If `magic` is absent, handling is profile-specific and may fall back to raw boot image behavior.
- If `magic` is present but `header_size`, `header_version`, profile, flags, size, or checksum are unsupported, the loader must reject the payload.
- The current stage-1 loader accepts only the v1 current-profile header inside
  the fixed `gros-stage2.gwo` stage-2 reservation.
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

- a general header classifier implementation
- a `.grw` compiler
- a linker
- relocation records
- symbol tables
- imported service tables
- executable loading in stage-2
- protected mode or long mode
- a boot banner change
