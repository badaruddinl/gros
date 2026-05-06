# GrSCall Service Registry

This document defines the first GrSCall service registry seed. `GrSCall` means
Gr System Call. It is the canonical public name for the GrOS service-call and
future syscall interface. `GrCall` is a deprecated alias and should not be used
for new public documentation.

This is a registry and stability contract for implemented and reserved service
selectors. It does not add a syscall table implementation, parser, compiler,
interpreter, linker, allocator, executable loader, hosted output, or boot banner
change.

## Current Profile

Current concrete runtime profile:

```txt
gros.x86.bios.real16.stage2.v0
```

Current GrSCall entry mechanism:

```txt
int 30h
```

This mechanism is profile-specific. The current `int 30h` path is a service
gate seed, not a complete OS syscall ABI. Future profiles may use different
machine entry mechanisms while preserving equivalent service semantics where
possible.

## Selector Encoding

For the current real16 seed:

```txt
AH = service group
AL = service id
```

Return convention:

```txt
CF = 0 success, AX = result
CF = 1 error,   AX = error code
```

Unsupported selector behavior:

```txt
CF = 1
AX = 0001h
```

## Implemented Services

| Group | Service | Name | Status |
| --- | --- | --- | --- |
| `00h` | `00h` | `runtime/control.probe` | implemented |
| `00h` | `02h` | `runtime/control.profile_id` | implemented |
| `01h` | `00h` | `console/text.write_cstr` | implemented |
| `01h` | `01h` | `console/text.write_char` | implemented |
| `01h` | `02h` | `console/text.write_crlf` | implemented |

## Implemented Service Contracts

### `00h:00h runtime/control.probe`

Purpose:

```txt
Confirm that the GrSCall gate is present.
```

Expected success:

```txt
CF = 0
AX = 0000h
```

### `00h:02h runtime/control.profile_id`

Purpose:

```txt
Return the current runtime profile identity.
```

Inputs:

```txt
none beyond the selector in AX
```

Expected success:

```txt
CF = 0
AX = 0000h
DS:SI = zero-terminated profile identity string
```

Current profile identity:

```txt
gros.x86.bios.real16.stage2.v0
```

The returned string pointer is profile-local static runtime data. Callers must
treat the pointed-to string as read-only.

### `01h:00h console/text.write_cstr`

Purpose:

```txt
Write a zero-terminated string through the current text console.
```

Inputs:

```txt
DS:SI = zero-terminated string pointer
```

Preservation seed:

```txt
SI is preserved by the service.
```

### `01h:01h console/text.write_char`

Purpose:

```txt
Write one character through the current text console.
```

Inputs:

```txt
BL = character byte
```

### `01h:02h console/text.write_crlf`

Purpose:

```txt
Write a carriage return byte (`0Dh`) followed by a line feed byte (`0Ah`)
through the current text console.
```

Inputs:

```txt
none beyond the selector in AX
```

Expected success:

```txt
CF = 0
AX = 0000h
```

Service-specific preservation:

```txt
SI is preserved by the current service implementation.
```

The current implementation writes through BIOS teletype output. It does not
define terminal modes, newline normalization beyond this fixed CR/LF pair,
cursor policy beyond BIOS behavior, page selection, encoding beyond bytes, or a
higher-level console driver model.

## Reserved Groups

The following groups are reserved names only. They are not implemented unless a
service appears in the implemented table above and is validated by byte-level
fixtures.

| Group | Namespace | Current Status |
| --- | --- | --- |
| `00h` | `runtime/control` | partially implemented |
| `01h` | `console/text` | partially implemented |
| `02h` | `memory/seed` | reserved/future |
| `03h` | `boot/info` | reserved/future |
| `04h` | `storage/block` | reserved/future |
| `05h` | `process/task` | reserved/future |
| `06h` | `time/timer` | reserved/future |
| `07h` | `input/key` | reserved/future |
| `08h` | `system/profile` | reserved/future |

## Candidate Next Services

These are candidates only. They are not implemented by this document:

| Group | Service | Name |
| --- | --- | --- |
| `00h` | `01h` | `runtime/control.version` |
| `01h` | `03h` | `console/text.clear` |
| `02h` | `00h` | `memory/seed.probe_map` |
| `03h` | `00h` | `boot/info.drive` |

## Stability Rules

- A selector must not be reused with a different meaning.
- Implemented selectors require validation before they are documented as
  implemented.
- Reserved selectors may be documented, but they must not be claimed as working.
- Unsupported selectors must keep the stable error convention.
- Service inputs, outputs, clobbers, and preservation rules must be documented
  before implementation.
- Cross-profile GrSCall semantics should remain stable even when the machine
  entry mechanism changes.

## Validation Rule

Implemented services must be covered by:

```txt
scripts/check_runtime_abi.sh
```

Additional services should extend static byte validation before being merged.

## Non-Goals

This registry does not add:

- a complete syscall ABI
- a kernel dispatch table
- user/kernel separation
- process or task services
- timer services
- storage services
- memory allocation services
- hosted-native service mapping
- a version bump
