# Repo Plan

## Initial Decision

Start with one repository:

```txt
gros/
```

Reasons:

- GrOS, GrBoot, `.gr`, `.gro`, and the initial documentation are still tightly connected.
- Bytes, formats, and naming philosophy may still change quickly.
- One repository keeps the early versions consistent.

## Do Not Split Repositories Yet

Multiple repositories only make sense after one component becomes independently useful:

```txt
gros/      OS, kernel, bootloader, ABI
grlang/    language, parser, compiler, portable stdlib
```

Or later:

```txt
gros/
grtoolchain/
grspec/
grapps/
```

## When to Split

Split repositories when:

- GrLang can build programs other than GrOS.
- GrASM has its own test suite.
- The `.gro` format is stable.
- Users can use GrLang without pulling in the GrOS kernel.
