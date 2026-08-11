; GrOS Grogan x86_64 BIOS profile bootstrap.
; The first 16-bit sectors remain the firmware handoff; long_mode is the
; product kernel entry for the bounded x86_64 profile seed.
bits 16
section .boot start=0 vstart=0x7c00

; The bootstrap image is intentionally larger than the original preview.  The
; BIOS loader reads the kernel portion in one bounded transfer; the build then
; appends the persistent GFS2 volume after that transfer window.  Keeping the
; sector count here and in the image builder prevents a partially loaded
; kernel from ever reaching long mode.
%define KERNEL_LOAD_SECTORS 228
%ifndef PROCESS_CREATE_TEST
%define PROCESS_CREATE_TEST 0
%endif
%ifndef RESOURCE_TEST
%define RESOURCE_TEST 0
%endif
%ifndef ATA_TEST_FAULT
%define ATA_TEST_FAULT 0
%endif
%include "kernel/self_hosting_abi.inc"
%define PAGE_SIZE 0x1000
%define USER_BASE 0x400000
%define USER_CODE 0x400000
%define MAX_PAYLOAD_PAGES 4
%define MAX_PAYLOAD_BYTES (MAX_PAYLOAD_PAGES * PAGE_SIZE)
%define MAX_GWO_IMAGE_BYTES (MAX_PAYLOAD_BYTES + 48)
%define USER_GUARD (USER_CODE + VM_BLOB_OFFSET + MAX_PAYLOAD_BYTES)
%define USER_STACK (USER_GUARD + PAGE_SIZE)
%define USER_STACK_TOP (USER_STACK + PAGE_SIZE)
%define VM_RUNTIME_BASE USER_STACK_TOP
%define USER_LIMIT 0x40000000
; Keep the fixed GrVM entry and the verified bytecode in separate user pages.
; The interpreter has grown beyond the original 0x400-byte inline prefix;
; sharing a page would let the payload overwrite its native dispatch loop.
%define VM_BLOB_OFFSET 0x1000
%define VM_STACK_BASE (USER_STACK + 0x80)
%define VM_STACK_SLOTS 192
%define VM_FRAME_BASE VM_RUNTIME_BASE
%define VM_FRAME_STRIDE 2080
%define VM_FRAME_LOCALS 24
%define VM_FRAME_COUNT 64
%define VM_FRAME_END (VM_FRAME_BASE + VM_FRAME_COUNT * VM_FRAME_STRIDE)
%define VM_FRAME_LIMIT VM_FRAME_END
; Hosted GrVM allocates byte constants from its 1 MiB memory arena.  The
; self-hosting compiler emits literals inside loops, so reserve a private
; 32-page constant arena after the frame records and keep the process heap
; above both regions.
%define VM_CONST_PAGES 32
%define VM_CONST_BASE ((VM_FRAME_END + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1))
%define VM_CONST_LIMIT (VM_CONST_BASE + VM_CONST_PAGES * PAGE_SIZE)
%define VM_CONST_CACHE_SLOTS 256
%define VM_CONST_CACHE_BYTES (VM_CONST_CACHE_SLOTS * 16)
%define VM_CONST_CACHE_BASE VM_CONST_LIMIT
%define VM_CONST_CACHE_LIMIT (VM_CONST_CACHE_BASE + VM_CONST_CACHE_BYTES)
%define VM_RUNTIME_PAGES ((VM_CONST_CACHE_LIMIT - VM_RUNTIME_BASE + PAGE_SIZE - 1) >> 12)
%define VM_RUNTIME_END VM_CONST_CACHE_LIMIT
%define VM_BUFFER (USER_STACK + 0xd80)
%define VM_CONST_CURSOR (VM_BUFFER + 0x200)
%define VM_INSTRUCTION_LIMIT 100000000
%define VM_PC_SLOT USER_STACK
%define VM_SP_SLOT (USER_STACK + 8)
%define VM_STEP_SLOT (USER_STACK + 16)
%define VM_LIMIT_SLOT (USER_STACK + 24)
%define VM_FP_SLOT (USER_STACK + 32)
%define VM_ENTRY_SLOT (USER_STACK + 40)
%define VM_CODE_LIMIT (USER_CODE + VM_BLOB_OFFSET + MAX_PAYLOAD_BYTES)
%define KERNEL_CR3 0x1000
%define KERNEL_PDPT 0x2000
%define KERNEL_PD 0x3000
%define KERNEL_USER_PT 0x7000
%define TSS_SELECTOR 0x38
%define MAX_FRAMES 768
%define FS_START_LBA 240
%define GFS_MAX_FILE_BYTES 65536
%define ATA_PRIMARY_DATA 0x1f0
%define ATA_PRIMARY_SECTOR_COUNT 0x1f2
%define ATA_PRIMARY_LBA0 0x1f3
%define ATA_PRIMARY_DRIVE 0x1f6
%define ATA_PRIMARY_STATUS 0x1f7

; Process object layout.  The object is intentionally fixed-size in Alpha so
; teardown can walk every owned frame without a hidden allocator dependency.
%define PROC_STATE 0
%define PROC_PID 4
%define PROC_PARENT 8
%define PROC_CR3 16
%define PROC_PDPT 24
%define PROC_PD 32
%define PROC_PT 40
%define PROC_CODE 48
%define PROC_STACK 56
%define PROC_KSTACK 64
%define PROC_KTOP 72
%define PROC_CONTEXT 80
%define PROC_RIP 88
%define PROC_RSP 96
%define PROC_FLAGS 104
%define PROC_EXIT_STATUS 108
%define PROC_NEXT 112
%define PROC_HEAP 120
%define PROC_HANDLE 128
%define PROC_OFFSET 136
%define PROC_INODE 144
%define PROC_FILE_SIZE 152
%define PROC_PAYLOAD_PAGES 160
%define PROC_ENTRY 168
%define PROC_ARG_PTR 176
%define PROC_ARG_LEN 184
%define PROC_SIZE 192
%define PROC_READY 1
%define PROC_RUNNING 2
%define PROC_BLOCKED 3
%define PROC_EXITED 4
%define MAX_PROCESS_ARGS 256

%include "kernel/entry.asm"
%include "kernel/proc/process.asm"
%include "kernel/runtime/loader.asm"
%include "kernel/proc/syscalls.asm"
%include "kernel/arch/x86_64/interrupts.asm"
%include "kernel/mm/memory.asm"
%include "kernel/proc/scheduler.asm"
%include "kernel/drivers/ata.asm"
%include "kernel/fs/gfs2.asm"
%include "kernel/drivers/console.asm"
%include "kernel/runtime/vm.asm"
%include "kernel/arch/x86_64/tables.asm"
%include "kernel/data.asm"
