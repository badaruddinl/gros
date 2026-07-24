# Headered Stage-2 Loader Contract

This contract defines the first executable use of the seeded `.gwo` header in
the current BIOS real16 boot container. It applies only to the stage-2 area of
`gros-stage2.gwo`; the legacy `gros-v0.5.gwo` boot sector remains raw-profile.

## Layout

```txt
LBA 0       stage-1 raw BIOS boot sector (512 bytes)
LBA 1..4    32-byte GWO header followed by a 2016-byte payload reservation
```

Stage-1 reads all four stage-2 sectors to `0000:8000`. The header resides at
`0000:8000`; payload byte zero resides at `0000:8020`.

## Accepted Header

The only accepted v1 profile is:

```txt
magic             GRO\0
header_size       32
header_version    0
profile_id        0 (gros.x86.bios.real16.stage2.v0)
flags             0
payload_checksum  0
reserved          all zero
payload_size      1..2016
entry_offset      less than payload_size
```

The stage-1 transfer target is `0000:(8020h + entry_offset)`. `DL` remains the
BIOS boot drive and the existing real16 segment/stack/DF state is restored
before transfer.

## Rejection

Any bad magic, unsupported field, zero/oversize payload, or out-of-range entry
must enter the loader error halt path. A malformed header must never fall back
to raw execution, and stage-1 must not transfer control before validation
completes.

## Scope Boundaries

This is an executable loader for the fixed stage-2 boot-container payload. It
does not add general disk discovery, filesystem loading, relocations, symbol
resolution, dynamic linking, a `.grw` compiler, or acceptance of arbitrary
host files.
