#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONTRACTS=${CONTRACTS:-"$ROOT/contracts/self-hosting-alpha"}
GWO2_DOC=${GWO2_DOC:-"$ROOT/docs/45-self-hosting-gwo2-grown-alpha-contract.md"}
fail() { echo "error: $1" >&2; exit 1; }
require_file() { [ -f "$CONTRACTS/$1" ] || fail "missing contract $1"; }
require_line() {
    local file=$1
    local line=$2
    # Contract fixtures historically carry CRLF because they are consumed by
    # Windows tooling as well as the WSL validation lane.  Compare logical
    # lines so the gate checks the contract content rather than its checkout
    # line-ending convention.
    grep -Fqx "$line" < <(tr -d '\r' < "$CONTRACTS/$file") || \
        fail "$file missing exact line: $line"
}

require_file process-layout.txt
require_line process-layout.txt 'schema=gros-process-address-space/v1'
require_line process-layout.txt 'page_size=4096'
require_line process-layout.txt 'user_base=0x0000000000400000'
require_line process-layout.txt 'guard_pages=1'
require_line process-layout.txt 'user_code_permission=RX'
require_line process-layout.txt 'user_data_permission=RW-NX'

require_file syscall-abi-v1.tsv
[ "$(wc -l < "$CONTRACTS/syscall-abi-v1.tsv" | tr -d ' ')" = 18 ] || fail 'syscall table must contain header plus 17 selectors'
require_line syscall-abi-v1.tsv $'selector\tname\tresult'
require_line syscall-abi-v1.tsv $'0x01\tconsole_read\tbytes-or-errno'
require_line syscall-abi-v1.tsv $'0x0b\tprocess_exit\tnoreturn'
require_line syscall-abi-v1.tsv $'0x0e\tfile_unlink\tzero-or-errno'
require_line syscall-abi-v1.tsv $'0x0f\tprocess_spawn\tpid-or-errno'
require_line syscall-abi-v1.tsv $'0x10\tprocess_wait\texit-status-or-errno'
require_line syscall-abi-v1.tsv $'0x11\tprocess_spawn_args(image,size,args,args_len:R8)\tpid-or-errno'
require_line syscall-abi-v1.tsv $'0x13\tfile_list\tbytes-or-errno'

require_file gwo2-import-abi-v1.tsv
[ "$(wc -l < "$CONTRACTS/gwo2-import-abi-v1.tsv" | tr -d ' ')" = 20 ] || fail 'GWO2 import ABI must contain header plus 19 imports'
require_line gwo2-import-abi-v1.tsv $'import_id\tname\targc\tresult\tsyscall_selector'
require_line gwo2-import-abi-v1.tsv $'14\ttask_yield\t0\tvoid\t12'
require_line gwo2-import-abi-v1.tsv $'16\tprocess_wait\t1\ti32\t16'

require_file gfs2-layout.txt
require_line gfs2-layout.txt 'schema=gros-gfs2/v1'
require_line gfs2-layout.txt 'block_size=512'
require_line gfs2-layout.txt 'primary_superblock=0'
require_line gfs2-layout.txt 'recovery_superblock=1'
require_line gfs2-layout.txt 'commit_marker=CMT2'

require_file gwo2-layout.txt
require_line gwo2-layout.txt 'schema=gros-gwo2/v1'
require_line gwo2-layout.txt 'magic=GWO2'
require_line gwo2-layout.txt 'header_size=32'
require_line gwo2-layout.txt 'bytecode_kind=1'
require_line gwo2-layout.txt 'loader_requires_checksum=true'
require_line gwo2-layout.txt 'verifier_requires_stack_effects=true'
require_line gwo2-layout.txt 'runtime_imports=1:print_i32,2:exit,3:newline,4:console_read,5:file_open,6:file_read,7:file_write,8:file_close,9:file_stat,10:mem_grow,11:path_create,12:file_unlink,13:print_bytes,14:task_yield,15:process_spawn,16:process_wait,17:process_spawn_args,18:process_args,19:file_list'

require_document_line() {
    local line=$1
    grep -Fqx "$line" < <(tr -d '\r' < "$GWO2_DOC") || \
        fail "GWO2 Markdown contract missing exact line: $line"
}

require_document_line 'ID 14 is the void scheduler boundary `task_yield()`; it returns no stack'

echo 'self-hosting contracts: process, syscall, GFS2, and GWO2 definitions ok'
