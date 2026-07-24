# QEMU Interaction Validation Contract

This document defines the deterministic QEMU interaction validation boundary
for the current GrRT16 stage-2 runtime. It adds test evidence only. It does not
add a GrSCall selector, serial driver, process model, loader, kernel, compiler,
profile change, or boot banner change.

## Scope

The current profile remains:

```txt
gros.x86.bios.real16.stage2.v0
```

The stage-2 runtime continues to use BIOS teletype output as its visible console
implementation. QEMU interaction validation mirrors every byte emitted through
the stage-2 string and character console paths to the QEMU debug console at I/O
port `E9h`.

The debug-console mirror is test transport only:

- it is not a new GrSCall service,
- it does not replace BIOS video output,
- it does not define a serial-port ABI,
- it does not change the user-visible command syntax,
- it must not be required by a non-QEMU target.

## Input Contract

The interaction runner uses QEMU monitor `sendkey` commands after the machine
has started. It sends one key at a time and terminates the run through the QEMU
monitor. The runner must bound each case with a timeout.

The validated input cases are:

- `help` followed by Enter,
- `ver` followed by Enter,
- an unknown command followed by Enter,
- Backspace editing before Enter,
- `cls` followed by Enter.

`reboot` remains covered by the stage-2 command byte fixtures and is not part of
the deterministic transcript suite because BIOS bootstrap restarts the machine.

## Output Contract

The debug transcript must show the stage-2 banner and prompt, then show the
typed command echo and its defined response.

Required response facts:

| Input | Required transcript fact |
| --- | --- |
| `help` | `help ver cls reboot` |
| `ver` | `GrOS v0.5` after the command echo |
| unknown input | `?` |
| Backspace edit | `x`, Backspace erase, then `help` appear as one edit sequence before the help response |
| `cls` | a new `ground> ` prompt is emitted |

## Validation Contract

Validation consists of:

- static image checks for the `out E9h, AL` mirror in both stage-2 console
  output paths,
- QEMU interaction cases with a captured debug-console transcript,
- negative tests for malformed runner input and QEMU failure handling,
- the existing boot, ABI, memory, data, command, and smoke validation paths.

The implementation sequence remains:

```txt
contract -> validation -> implementation -> claim
```

## Non-Goals

This contract does not add:

- a serial driver,
- COM-port initialization,
- persistent logging,
- a terminal protocol,
- a new console selector,
- a new runtime profile,
- a new boot stage,
- Grogan kernel ownership,
- Grown compiler support.
