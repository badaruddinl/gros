# Release Readiness Handoff

The current `development` baseline is release-ready for its declared seed scope.
The reproducible gate is:

```bash
make release-ready
```

It runs the full static/negative validation suite, normal stage-2 QEMU smoke and
interaction cases, the compiled minimal-main payload trace, and malformed-header
runtime rejection. A clean Git worktree after this gate is the final handoff
condition.

## Implemented Evidence

| Phase | Evidence |
| --- | --- |
| 0 | deterministic development validation baseline |
| 1 | QEMU prompt interaction transcript gate |
| 2 | expected-only `grabi.real16.call.v1` fixture validation |
| 3 | fixed v1 headered stage-2 loader and rejection contract |
| 4 | minimal `.grw` main compiler through headered QEMU execution |
| 5 | CRLF and line-comment normalization with bounded parser rejection |
| 6 | QEMU proof malformed header does not execute `0000:8020` |
| 7 | `release-ready` aggregate gate and this handoff |

## Scope Boundaries

This readiness claim does not claim a general Grown compiler, general executable
loader, call-ABI code generation, filesystem, process model, kernel, allocator,
protected mode, UEFI, or hosted-native output. The compiler accepts only the
minimal documented `main` subset.

## Handoff Commands

```bash
make release-ready
git status --short --branch
```

Expected release evidence includes a successful gate, matching `build` and
tracked `dist` boot artifacts, passing QEMU traces, and no uncommitted files.
