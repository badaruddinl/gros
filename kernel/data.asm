phys_first_free:
    dq 0
phys_frame_count:
    dd 0
align 8
frame_pool:
    times MAX_FRAMES dq 0
frame_used:
    times MAX_FRAMES db 0
frame_owner:
    times MAX_FRAMES dd 0
paging_window_end:
    dq 0
heap_base:
    dq 0
heap_slot_count:
    dd 0
heap_probe_one:
    dq 0
align 8
heap_bitmap:
    times 256 db 0
heap_next:
    dq 0
heap_end:
    dq 0
run_queue:
    dq 0
scheduler_task_one:
    dq 0
scheduler_task_two:
    dq 0
scheduler_current:
    dq 0
scheduler_kernel_context:
    dq 0
timer_seen:
    db 0
last_scancode:
    db 0
fs_loaded:
    db 0
align 8
fs_payload_copy:
    dq 0
user_syscall_seen:
    db 0
user_done:
    db 0
align 8
user_saved_rip:
    dq 0
user_saved_flags:
    dq 0
user_saved_rsp:
    dq 0
align 16
process_one:
    times PROC_SIZE db 0
process_two:
    times PROC_SIZE db 0
align 16
process_one_args:
    times MAX_PROCESS_ARGS db 0
process_two_args:
    times MAX_PROCESS_ARGS db 0
%if PROCESS_CREATE_TEST
align 4
process_create_test_armed:
    dd 0
process_create_test_attempt:
    dd 0
process_create_test_counter:
    dd 0
process_create_test_active:
    dd 0
%endif
%if RESOURCE_TEST
align 4
resource_test_frames_live:
    dd 0
resource_test_handles_live:
    dd 0
resource_test_hex:
    db '0123456789ABCDEF'
%endif
current_process:
    dq 0
user_payload_size:
    dd 0
user_payload_entry:
    dd 0
align 8
gwo2_boundaries:
    times MAX_PAYLOAD_BYTES db 0
gwo2_depths:
    times MAX_PAYLOAD_BYTES db 0
ata_ready:
    db 0
ata_failure_code:
    db 0
gfs_mount_valid:
    db 0
align 8
ata_capacity:
    dq 0
gfs_total_blocks:
    dq 0
gfs_active_super:
    db 0
align 8
gfs_bitmap_buffer:
    times 512 db 0
gfs_inode_block:
    times 512 db 0
gfs_dir_buffer:
    times 512 db 0
gfs_data_buffer:
    times 512 db 0
gfs_path_buffer:
    times 32 db 0
align 8
gfs_io_user:
    dq 0
gfs_io_size:
    dq 0
gfs_io_start:
    dd 0
gfs_io_blocks:
    dd 0
align 512
ata_identify_buffer:
    times 512 db 0
gfs_super_buffer:
    times 512 db 0
gfs_recovery_buffer:
    times 512 db 0
align 4096
user_payload_kernel:
    times MAX_GWO_IMAGE_BYTES db 0
align 4096
user_gwo_staging:
    times MAX_GWO_IMAGE_BYTES db 0
shell_len:
    db 0
shell_done:
    db 0
vga_cursor:
    dq 0
shell_buffer:
    times 64 db 0
console_input_head:
    db 0
console_input_tail:
    db 0
align 16
console_input_buffer:
    times 256 db 0
shell_banner:
    db 13, 10, 'GrOS x86_64', 13, 10, 0
shell_prompt:
    db 'Grogan> ', 0
shell_help:
    db 'help ls cat save mem tasks reboot', 13, 10, 0
shell_line_end:
    db 13, 10, 0
shell_cat_separator:
    db ': ', 0
shell_mem:
    db 'FRAMES HEAP PAGES', 13, 10, 0
shell_tasks:
    db 'T1 T2', 13, 10, 0
shell_reboot:
    db 'REBOOT', 13, 10, 0
shell_save_ok:
    db 'SAVE OK', 13, 10, 0
shell_unknown:
    db '?', 13, 10, 0
cmd_help:
    db 'help', 0
cmd_ls:
    db 'ls', 0
cmd_cat:
    db 'cat', 0
cmd_mem:
    db 'mem', 0
cmd_tasks:
    db 'tasks', 0
cmd_save:
    db 'save', 0
cmd_reboot:
    db 'reboot', 0
gfs_shell_name:
    db 'hello.grw', 0
gfs_shell_name_end:
gfs_shell_source:
    db 'target "gros.x86.bios.longmode.grogan.v1"', 10
    db 'fn main() -> void {', 10
    db '    print_i32(28);', 10
    db '}', 10
gfs_shell_source_end:
align 16
user_gwo_image:
    incbin "build/generated/grogan-user.gwo"
user_gwo_image_end:
align 16
user_helper_image:
    incbin "build/generated/grogan-helper.gwo"
user_helper_image_end:
align 16
fs_image:
    dd 0x31534647 ; GFS1
    dd 1          ; root-entry count
fs_entry:
    dd 0x54494e49 ; INIT
    dd 4          ; payload size
    dq fs_payload
fs_payload:
    db 'GRFS'
times 512*KERNEL_LOAD_SECTORS-($-$$) db 0
