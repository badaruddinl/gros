#!/usr/bin/env bash
set -euo pipefail

# Parse every ABI row and prove that the Rust bootstrap, Grown compiler, and
# NASM runtime all expose the same IDs, arities, result shapes, and selectors.
# The checked-in NASM include is generated from the TSVs; a stale include is a
# release failure rather than a warning.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import csv
import os
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
contracts = pathlib.Path(os.environ.get("SELF_HOSTING_ABI_CONTRACTS", root / "contracts/self-hosting-alpha"))
syscall_path = contracts / "syscall-abi-v1.tsv"
import_path = contracts / "gwo2-import-abi-v1.tsv"
rust_path = pathlib.Path(os.environ.get("SELF_HOSTING_ABI_RUST", root / "tools/grc0.rs"))
grown_path = pathlib.Path(os.environ.get("SELF_HOSTING_ABI_GROWN", root / "examples/grown-alpha/grc1.grw"))
rust = rust_path.read_text(encoding="utf-8")
grown = grown_path.read_text(encoding="utf-8")
kernel = "\n".join(path.read_text(encoding="utf-8") for path in sorted((root / "kernel").rglob("*.asm")))
grvm = (root / "tools/grvm.c").read_text(encoding="utf-8")

def read_table(path, header):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle, delimiter="\t"))
    if not rows or rows[0] != header:
        raise SystemExit(f"{path}: unexpected header")
    if any(len(row) != len(header) or any(not cell for cell in row) for row in rows[1:]):
        raise SystemExit(f"{path}: empty or malformed field")
    return [dict(zip(header, row)) for row in rows[1:]]

syscalls = read_table(syscall_path, ["selector", "name", "result"])
imports = read_table(import_path, ["import_id", "name", "argc", "result", "syscall_selector"])

def fail(message):
    raise SystemExit(f"{message}")

if len(syscalls) != 17:
    fail(f"expected 17 syscall rows, got {len(syscalls)}")
if len(imports) != 19:
    fail(f"expected 19 import rows, got {len(imports)}")

syscall_by_name = {}
syscall_by_selector = {}
allowed_results = {
    "bytes-or-errno", "handle-or-errno", "previous-break-or-errno",
    "zero-or-errno", "pid-or-errno", "exit-status-or-errno", "noreturn",
}
canonical_syscall_results = {
    "console_read": "bytes-or-errno", "console_write": "bytes-or-errno",
    "file_open": "handle-or-errno", "file_read": "bytes-or-errno",
    "file_write": "bytes-or-errno", "file_close": "zero-or-errno",
    "file_stat": "zero-or-errno", "mem_grow": "previous-break-or-errno",
    "process_exit": "noreturn", "task_yield": "zero-or-errno",
    "path_create": "handle-or-errno", "file_unlink": "zero-or-errno",
    "process_spawn": "pid-or-errno", "process_wait": "exit-status-or-errno",
    "process_spawn_args(image,size,args,args_len:R8)": "pid-or-errno",
    "process_args": "bytes-or-errno", "file_list": "bytes-or-errno",
}
for row in syscalls:
    selector = row["selector"]
    if not re.fullmatch(r"0x[0-9a-fA-F]{2}", selector):
        fail(f"invalid syscall selector {selector}")
    value = int(selector, 16)
    if value in syscall_by_selector:
        fail(f"duplicate syscall selector {selector}")
    if row["name"] in syscall_by_name:
        fail(f"duplicate syscall name {row['name']}")
    if row["result"] not in allowed_results:
        fail(f"unknown syscall result {row['result']}")
    if canonical_syscall_results.get(row["name"]) != row["result"]:
        fail(f"syscall result contract drift for {row['name']}")
    syscall_by_name[row["name"]] = row
    syscall_by_name[row["name"].split("(", 1)[0]] = row
    syscall_by_selector[value] = row

expected_selectors = {1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14, 15, 16, 17, 18, 19}
if set(syscall_by_selector) != expected_selectors:
    fail("syscall selector set is incomplete or contains an undocumented selector")

import_by_name = {}
import_by_id = {}
seen_selectors = {}
canonical_import_specs = {
    "print_i32": (1, "void"), "exit": (1, "noreturn"), "newline": (0, "void"),
    "console_read": (2, "i32"), "file_open": (2, "i32"), "file_read": (3, "i32"),
    "file_write": (3, "i32"), "file_close": (1, "i32"), "file_stat": (2, "i32"),
    "mem_grow": (1, "i32"), "path_create": (1, "i32"), "file_unlink": (1, "i32"),
    "print_bytes": (2, "void"), "task_yield": (0, "void"), "process_spawn": (2, "i32"),
    "process_wait": (1, "i32"), "process_spawn_args": (4, "i32"),
    "process_args": (2, "i32"), "file_list": (2, "i32"),
}
for row in imports:
    try:
        import_id = int(row["import_id"])
        argc = int(row["argc"])
    except ValueError:
        fail(f"non-numeric import ID/argc in {row}")
    if not 1 <= import_id <= 19:
        fail(f"import ID outside 1..19: {import_id}")
    if argc < 0 or argc > 4:
        fail(f"invalid import argc for {row['name']}: {argc}")
    if import_id in import_by_id or row["name"] in import_by_name:
        fail(f"duplicate import ID/name: {row['name']}")
    if row["result"] not in {"i32", "void", "noreturn"}:
        fail(f"unknown import result for {row['name']}: {row['result']}")
    if canonical_import_specs.get(row["name"]) != (argc, row["result"]):
        fail(f"import signature contract drift for {row['name']}")
    selector = row["syscall_selector"]
    if selector != "-":
        if not selector.isdigit() or int(selector) not in syscall_by_selector:
            fail(f"import {row['name']} has an unmapped syscall selector {selector}")
        if int(selector) in seen_selectors:
            fail(f"duplicate syscall mapping {selector} for {row['name']} and {seen_selectors[int(selector)]}")
        seen_selectors[int(selector)] = row["name"]
    import_by_id[import_id] = row
    import_by_name[row["name"]] = row

if set(import_by_id) != set(range(1, 20)):
    fail("import IDs must be exactly 1..19")
expected_runtime = {"print_i32", "exit", "newline"}
if {name for name, row in import_by_name.items() if row["syscall_selector"] == "-"} != expected_runtime:
    fail("runtime-only import set drifted")

expected_mapping = {
    "console_read": "console_read", "file_open": "file_open", "file_read": "file_read",
    "file_write": "file_write", "file_close": "file_close", "file_stat": "file_stat",
    "mem_grow": "mem_grow", "path_create": "path_create", "file_unlink": "file_unlink",
    "task_yield": "task_yield", "process_spawn": "process_spawn", "process_wait": "process_wait",
    "process_spawn_args": "process_spawn_args", "process_args": "process_args", "file_list": "file_list",
    "print_bytes": "console_write",
}
for import_name, syscall_name in expected_mapping.items():
    row = import_by_name[import_name]
    if int(row["syscall_selector"]) != int(syscall_by_name[syscall_name]["selector"], 16):
        fail(f"selector/name mapping drift for {import_name}")

# Rust maps ordinary imports in one match arm and handles the void scheduler
# import as an explicit special case.  Validate both the table-driven values
# and the special import IDs rather than checking only a few selected lines.
for name, row in import_by_name.items():
    if name in {"print_i32", "exit", "newline"}:
        if f'"{name}"' not in rust:
            fail(f"Rust compiler missing runtime import {name}")
        continue
    if name == "print_bytes":
        if 'name == "print_bytes"' not in rust:
            fail("Rust compiler missing print_bytes")
        continue
    if name == "task_yield":
        if '"task_yield"' not in rust or "emit(14)" not in rust:
            fail("Rust compiler task_yield lowering drift")
        continue
    pattern = rf'"{re.escape(name)}"\s*=>\s*\(({row["argc"]})\s*,\s*{row["import_id"]}\)'
    if not re.search(pattern, rust):
        fail(f"Rust import lowering drift: {name}")
    if f"id == {row['import_id']}" not in grvm:
        fail(f"C verifier/VM import dispatch drift: {name}")

for name, row in import_by_name.items():
    import_id = row["import_id"]
    if f'name_eq(call_name, "{name}")' not in grown:
        fail(f"Grown compiler missing import {name}")
    if f'emit8(state, {import_id})' not in grown:
        fail(f"Grown compiler import ID drift: {name}")

# A void import must not be lowered as an expression result.  In particular,
# task_yield resumes the scheduler without pushing a value; treating it as an
# i32 makes statement lowering append opcode 19 (drop), which underflows the
# child VM stack and is invisible to a text-only ABI check.  Inspect the whole
# special-case body so this contract cannot drift while IDs still match.
task_yield_branch = re.search(
    r'if \(name_eq\(call_name, "task_yield"\) == 1\) \{([^}]*)\}',
    grown,
    re.S,
)
if not task_yield_branch:
    fail("Grown compiler task_yield lowering branch missing")
task_yield_body = task_yield_branch.group(1)
if "emit8(state, 14)" not in task_yield_body:
    fail("Grown compiler task_yield import ID drift")
if re.search(r"\bresult\s*=\s*1\b", task_yield_body):
    fail("Grown compiler task_yield must remain void; result flag drifted to i32")

def macro_name(prefix, name):
    return prefix + re.sub(r"[^A-Za-z0-9]+", "_", name.split("(", 1)[0]).strip("_").upper()

for row in syscalls:
    macro = macro_name("SYS_", row["name"])
    if f"%define {macro} {row['selector'].lower()}" not in (root / "kernel/self_hosting_abi.inc").read_text(encoding="utf-8"):
        fail(f"generated syscall constant missing: {macro}")
    if f"cmp eax, strict byte {macro}" not in kernel and f"mov eax, {macro}" not in kernel:
        fail(f"kernel does not consume generated syscall constant: {macro}")
for row in imports:
    macro = macro_name("GWO_IMPORT_", row["name"])
    if f"%define {macro} {row['import_id']}" not in (root / "kernel/self_hosting_abi.inc").read_text(encoding="utf-8"):
        fail(f"generated import constant missing: {macro}")
    if f"cmp eax, strict byte {macro}" not in kernel:
        fail(f"kernel does not consume generated import constant: {macro}")

if not os.environ.get("SELF_HOSTING_ABI_SKIP_GENERATED"):
    with tempfile.NamedTemporaryFile() as generated:
        subprocess.run([str(root / "scripts/generate_self_hosting_abi.sh"), generated.name], check=True)
        if pathlib.Path(generated.name).read_bytes() != (root / "kernel/self_hosting_abi.inc").read_bytes():
            fail("kernel/self_hosting_abi.inc is stale; regenerate it from the TSV contracts")

print("Grogan import ABI parity: full TSV parser, generated constants, Rust, Grown, and kernel dispatch agree")
PY
