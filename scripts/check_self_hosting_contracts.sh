#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONTRACTS=${CONTRACTS:-"$ROOT/contracts/self-hosting-alpha"}
fail() { echo "error: $1" >&2; exit 1; }
require_file() { [ -f "$CONTRACTS/$1" ] || fail "missing contract $1"; }
require_line() {
    local file=$1
    local line=$2
    grep -Fqx "$line" "$CONTRACTS/$file" || fail "$file missing exact line: $line"
}

require_file process-layout.txt
require_line process-layout.txt 'schema=gros-process-address-space/v1'
require_line process-layout.txt 'page_size=4096'
require_line process-layout.txt 'user_base=0x0000000000400000'
require_line process-layout.txt 'guard_pages=1'
require_line process-layout.txt 'user_code_permission=RX'
require_line process-layout.txt 'user_data_permission=RW-NX'

require_file syscall-abi-v1.tsv
[ "$(wc -l < "$CONTRACTS/syscall-abi-v1.tsv" | tr -d ' ')" = 15 ] || fail 'syscall table must contain header plus 14 selectors'
require_line syscall-abi-v1.tsv $'selector\tname\tresult'
require_line syscall-abi-v1.tsv $'0x01\tconsole_read\tbytes-or-errno'
require_line syscall-abi-v1.tsv $'0x0b\tprocess_exit\tnoreturn'
require_line syscall-abi-v1.tsv $'0x0e\tfile_unlink\tzero-or-errno'

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

echo 'self-hosting contracts: process, syscall, GFS2, and GWO2 definitions ok'
