.PHONY: build check test policy project-policy-failures status-consistency status-consistency-failures self-hosting-contracts self-hosting-contract-failures gfs2-host gfs2-host-failures gwo2-host gwo2-host-failures grogan-seed grogan-seed-failures grogan-seed-qemu longmode-image longmode-image-failures longmode-qemu generated-fixtures generated-fixtures-failures grabi-generated-code grabi-generated-code-failures minimal-main minimal-main-failures minimal-main-qemu headered-stage2-rejection headered-stage2-rejection-failures release-ready validate-release validate-self-host validation-lanes-failures boot-image-failures grscall-registry grscall-registry-failures gwo-header-fixtures gwo-header-fixture-failures gwo-artifact-inventory gwo-artifact-inventory-failures validate validate-static validate-static-internal validate-qemu validate-qemu-internal stage2 check-stage2 stage2-image-failures headered-stage2 headered-stage2-failures runtime-abi runtime-abi-failures memory-model memory-model-failures near-pointers near-pointers-failures stage2-data stage2-data-failures stage2-commands stage2-command-failures stage2-input stage2-input-failures stage2-debugcon stage2-debugcon-failures smoke-stage2-failures smoke-stage2 run run-stage2 clean

BUILD_IMAGE := build/gros-v0.5.gwo
DIST_IMAGE := dist/gros-v0.5.gwo
STAGE2_BUILD_IMAGE := build/gros-stage2.gwo
STAGE2_DIST_IMAGE := dist/gros-stage2.gwo
LONGMODE_BUILD_IMAGE := build/gros-longmode.img
LONGMODE_DIST_IMAGE := dist/gros-longmode.img

.PHONY: grogan-x86_64-image grogan-x86_64-image-failures grogan-x86_64-qemu grogan-interrupts grogan-interrupt-failures grogan-scheduler grogan-scheduler-failures grogan-syscalls grogan-syscall-failures grogan-processes grogan-process-failures grogan-process-qemu grogan-process-create-failures-qemu grogan-resource-leaks-qemu grogan-storage grogan-storage-qemu grogan-storage-syscall-qemu grogan-functions-qemu grogan-compiler grogan-compiler-failures grogan-compiler-corpus self-hosting-abi-generate grogan-import-abi-parity grogan-import-abi-failures grogan-release-exclusions grogan-longmode-modularity grogan-compiler-bounds-qemu grogan-self-host grogan-self-host-qemu grogan-general-shell-qemu grogan-modules-qemu grogan-corruption-qemu grogan-boundaries-qemu grogan-ata-failures-qemu grogan-oom-qemu grogan-reliability-qemu grogan-clean-checkout grogan-release grogan-release-failures grogan-shell-check grogan-shell-failures grogan-shell-qemu

build:
	./scripts/build_boot.sh

check: build
	./scripts/check_boot.sh

test:
	./scripts/test_gwnraw.sh

policy:
	./scripts/check_project_policy.sh

project-policy-failures:
	./scripts/test_project_policy_failures.sh

self-hosting-contracts:
	./scripts/check_self_hosting_contracts.sh

self-hosting-abi-generate:
	./scripts/generate_self_hosting_abi.sh kernel/self_hosting_abi.inc

self-hosting-contract-failures:
	./scripts/test_self_hosting_contract_failures.sh

gfs2-host:
	./scripts/check_gfs2_host.sh

gfs2-host-failures:
	./scripts/test_gfs2_host_failures.sh

gwo2-host:
	./scripts/check_gwo2_host.sh

gwo2-host-failures:
	./scripts/test_gwo2_host_failures.sh

status-consistency:
	./scripts/check_status_consistency.sh

status-consistency-failures:
	./scripts/test_status_consistency_failures.sh

grogan-seed: stage2
	./scripts/check_grogan_seed.sh $(STAGE2_BUILD_IMAGE)

grogan-seed-failures:
	./scripts/test_grogan_seed_failures.sh

grogan-seed-qemu: grogan-seed
	./scripts/qemu_grogan_seed.sh $(STAGE2_BUILD_IMAGE)

generated-fixtures:
	./scripts/check_generated_fixtures.sh

generated-fixtures-failures:
	./scripts/test_generated_fixtures_failures.sh

grabi-generated-code: generated-fixtures
	./scripts/check_grabi_generated_code.sh

grabi-generated-code-failures:
	./scripts/test_grabi_generated_code_failures.sh

minimal-main:
	./scripts/grw_minimal_main.sh examples/generated/minimal-main-void.grw build/generated/minimal-main-void.gwn
	./scripts/build_headered_payload_image.sh build/generated/minimal-main-void.gwn build/generated/minimal-main-void.gwo
	./scripts/check_grw_minimal_main.sh

minimal-main-failures:
	./scripts/test_grw_minimal_main_failures.sh

minimal-main-qemu: minimal-main
	./scripts/qemu_generated_minimal_main.sh

headered-stage2-rejection: stage2
	./scripts/qemu_headered_stage2_rejection.sh $(STAGE2_BUILD_IMAGE)

headered-stage2-rejection-failures:
	./scripts/test_qemu_headered_stage2_rejection_failures.sh

release-ready: validate-static validate-qemu
	@echo "ok: release readiness gate"

validate-release: release-ready grogan-reliability-qemu grogan-clean-checkout

validate-self-host: grogan-self-host grogan-self-host-qemu

validation-lanes-failures:
	./scripts/test_validation_lanes_failures.sh

boot-image-failures:
	./scripts/test_boot_image_failures.sh

grscall-registry:
	./scripts/check_grscall_registry.sh

grscall-registry-failures:
	./scripts/test_grscall_registry_failures.sh

gwo-header-fixtures:
	./scripts/check_gwo_header_fixtures.sh

gwo-header-fixture-failures:
	./scripts/test_gwo_header_fixture_failures.sh

gwo-artifact-inventory:
	./scripts/check_gwo_artifact_inventory.sh

gwo-artifact-inventory-failures:
	./scripts/test_gwo_artifact_inventory_failures.sh

validate: validate-static

validate-static:
	./scripts/run_validation_lane.sh static "$(MAKE)" --no-print-directory validate-static-internal

validate-static-internal: policy project-policy-failures self-hosting-contracts self-hosting-contract-failures grogan-import-abi-parity grogan-import-abi-failures grogan-release-exclusions grogan-longmode-modularity gfs2-host gfs2-host-failures gwo2-host gwo2-host-failures status-consistency status-consistency-failures grogan-seed grogan-seed-failures grogan-self-host grogan-x86_64-image grogan-x86_64-image-failures grogan-interrupts grogan-interrupt-failures grogan-scheduler grogan-scheduler-failures grogan-syscalls grogan-syscall-failures grogan-processes grogan-process-failures grogan-storage grogan-compiler grogan-compiler-failures grogan-compiler-corpus grogan-release grogan-release-failures grogan-shell-check grogan-shell-failures longmode-image-failures generated-fixtures generated-fixtures-failures grabi-generated-code-failures minimal-main minimal-main-failures headered-stage2-rejection-failures boot-image-failures grscall-registry grscall-registry-failures gwo-header-fixtures gwo-header-fixture-failures gwo-artifact-inventory gwo-artifact-inventory-failures runtime-abi-failures stage2-image-failures headered-stage2-failures memory-model-failures stage2-data-failures near-pointers-failures stage2-command-failures stage2-input-failures stage2-debugcon-failures qemu-interaction-failures smoke-stage2-failures validation-lanes-failures test check stage2
	./scripts/check_boot.sh $(DIST_IMAGE)
	./scripts/validate_boot_image.sh --require-ndisasm $(BUILD_IMAGE)
	./scripts/validate_boot_image.sh --require-ndisasm $(DIST_IMAGE)
	cmp -s $(BUILD_IMAGE) $(DIST_IMAGE)
	./scripts/check_stage2_image.sh --require-ndisasm $(STAGE2_BUILD_IMAGE)
	./scripts/check_stage2_image.sh --require-ndisasm $(STAGE2_DIST_IMAGE)
	./scripts/check_headered_stage2_loader.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_headered_stage2_loader.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_memory_model.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_memory_model.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_near_pointers.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_near_pointers.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_stage2_data.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_stage2_data.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_stage2_commands.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_stage2_commands.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_stage2_input.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_stage2_input.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_stage2_debugcon.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_stage2_debugcon.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_runtime_abi.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_runtime_abi.sh $(STAGE2_DIST_IMAGE)
	./scripts/check_grabi_generated_code.sh
	cmp -s $(STAGE2_BUILD_IMAGE) $(STAGE2_DIST_IMAGE)
	./scripts/check_longmode_image.sh $(LONGMODE_DIST_IMAGE)
	./scripts/check_grogan_x86_64_profile.sh $(LONGMODE_DIST_IMAGE)
	./scripts/check_grogan_interrupts.sh $(LONGMODE_DIST_IMAGE)
	cmp -s $(LONGMODE_BUILD_IMAGE) $(LONGMODE_DIST_IMAGE)
	@echo "ok: build matches dist artifacts"

validate-qemu:
	./scripts/run_validation_lane.sh qemu "$(MAKE)" --no-print-directory validate-qemu-internal

validate-qemu-internal: smoke-stage2 qemu-interaction minimal-main-qemu headered-stage2-rejection grogan-x86_64-qemu grogan-process-qemu grogan-process-create-failures-qemu grogan-resource-leaks-qemu grogan-compiler-bounds-qemu grogan-storage-qemu grogan-storage-syscall-qemu grogan-functions-qemu grogan-shell-qemu grogan-general-shell-qemu grogan-modules-qemu grogan-corruption-qemu grogan-boundaries-qemu grogan-ata-failures-qemu grogan-oom-qemu grogan-self-host-qemu

grogan-x86_64-image:
	./scripts/build_longmode_image.sh $(LONGMODE_BUILD_IMAGE)
	mkdir -p "$(dir $(LONGMODE_DIST_IMAGE))"
	cp $(LONGMODE_BUILD_IMAGE) $(LONGMODE_DIST_IMAGE)
	./scripts/check_longmode_image.sh $(LONGMODE_BUILD_IMAGE)
	./scripts/check_grogan_x86_64_profile.sh $(LONGMODE_BUILD_IMAGE)

grogan-x86_64-image-failures:
	./scripts/test_grogan_x86_64_profile_failures.sh

grogan-interrupts: grogan-x86_64-image
	./scripts/check_grogan_interrupts.sh $(LONGMODE_BUILD_IMAGE)

grogan-interrupt-failures:
	./scripts/test_grogan_interrupt_failures.sh

grogan-scheduler: grogan-x86_64-image
	./scripts/check_grogan_scheduler.sh $(LONGMODE_BUILD_IMAGE)

grogan-scheduler-failures:
	./scripts/test_grogan_scheduler_failures.sh

grogan-syscalls: grogan-x86_64-image
	./scripts/check_grogan_syscalls.sh $(LONGMODE_BUILD_IMAGE)

grogan-syscall-failures:
	./scripts/test_grogan_syscall_failures.sh

grogan-processes: grogan-x86_64-image
	./scripts/check_grogan_processes.sh $(LONGMODE_BUILD_IMAGE)

grogan-process-failures:
	./scripts/test_grogan_process_failures.sh

grogan-process-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_fault_isolation.sh

grogan-process-create-failures-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_process_create_failures.sh

grogan-storage: grogan-x86_64-image
	./scripts/check_grogan_storage.sh $(LONGMODE_BUILD_IMAGE)

grogan-storage-qemu: grogan-x86_64-image
	./scripts/qemu_longmode_image.sh

grogan-storage-syscall-qemu:
	./scripts/qemu_grogan_storage_syscalls.sh

grogan-functions-qemu:
	./scripts/qemu_grogan_functions.sh

grogan-compiler:
	./scripts/check_grogan_compiler.sh

grogan-compiler-failures:
	./scripts/test_grogan_compiler_failures.sh

grogan-compiler-corpus:
	./scripts/check_grogan_compiler_corpus.sh

grogan-import-abi-parity: self-hosting-contracts
	./scripts/check_grogan_import_abi_parity.sh

grogan-import-abi-failures:
	./scripts/test_grogan_import_abi_failures.sh

grogan-release-exclusions:
	./scripts/check_grogan_release_exclusions.sh

grogan-longmode-modularity:
	./scripts/check_grogan_longmode_modularity.sh

grogan-compiler-bounds-qemu:
	./scripts/qemu_grogan_compiler_bounds.sh

grogan-resource-leaks-qemu:
	./scripts/qemu_grogan_resource_leaks.sh

grogan-self-host:
	./scripts/check_grogan_self_host.sh

grogan-self-host-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_self_host.sh

grogan-general-shell-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_general_shell.sh

grogan-modules-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_modules.sh

grogan-corruption-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_corruption.sh

grogan-boundaries-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_boundaries.sh

grogan-ata-failures-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_ata_failures.sh

grogan-oom-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_oom.sh

grogan-reliability-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_reliability.sh

grogan-release:
	./scripts/check_grogan_release.sh

grogan-clean-checkout:
	./scripts/check_grogan_clean_checkout.sh

grogan-release-failures:
	./scripts/test_grogan_release_failures.sh

grogan-shell-check: grogan-x86_64-image
	./scripts/check_grogan_shell.sh $(LONGMODE_BUILD_IMAGE)

grogan-shell-failures:
	./scripts/test_grogan_shell_failures.sh

grogan-shell-qemu: grogan-x86_64-image
	./scripts/qemu_grogan_shell.sh $(LONGMODE_BUILD_IMAGE)

longmode-image: grogan-x86_64-image

longmode-image-failures:
	./scripts/test_longmode_image_failures.sh

grogan-x86_64-qemu: grogan-x86_64-image
	./scripts/qemu_longmode_image.sh

longmode-qemu: grogan-x86_64-qemu

stage2:
	./scripts/build_stage2_image.sh

check-stage2: stage2
	./scripts/check_stage2_image.sh --require-ndisasm

stage2-image-failures:
	./scripts/test_stage2_image_failures.sh

headered-stage2: stage2
	./scripts/check_headered_stage2_loader.sh $(STAGE2_BUILD_IMAGE)

headered-stage2-failures:
	./scripts/test_headered_stage2_loader_failures.sh

runtime-abi: stage2
	./scripts/check_runtime_abi.sh $(STAGE2_BUILD_IMAGE)

runtime-abi-failures:
	./scripts/test_runtime_abi_failures.sh

memory-model: stage2
	./scripts/check_memory_model.sh $(STAGE2_BUILD_IMAGE)

memory-model-failures:
	./scripts/test_memory_model_failures.sh

near-pointers: stage2
	./scripts/check_near_pointers.sh $(STAGE2_BUILD_IMAGE)

near-pointers-failures:
	./scripts/test_near_pointers_failures.sh

stage2-data: stage2
	./scripts/check_stage2_data.sh $(STAGE2_BUILD_IMAGE)

stage2-data-failures:
	./scripts/test_stage2_data_failures.sh

stage2-commands: stage2
	./scripts/check_stage2_commands.sh $(STAGE2_BUILD_IMAGE)

stage2-command-failures:
	./scripts/test_stage2_commands_failures.sh

stage2-input: stage2
	./scripts/check_stage2_input.sh $(STAGE2_BUILD_IMAGE)

stage2-input-failures:
	./scripts/test_stage2_input_failures.sh

stage2-debugcon: stage2
	./scripts/check_stage2_debugcon.sh $(STAGE2_BUILD_IMAGE)

stage2-debugcon-failures:
	./scripts/test_stage2_debugcon_failures.sh

qemu-interaction: stage2 stage2-debugcon
	@for case_name in help ver unknown backspace cls; do \
		./scripts/qemu_stage2_interaction.sh --case $$case_name --require-qemu $(STAGE2_BUILD_IMAGE); \
	done

qemu-interaction-failures:
	./scripts/test_qemu_stage2_interaction_failures.sh

smoke-stage2: stage2
	./scripts/smoke_stage2_qemu.sh --require-qemu

smoke-stage2-failures:
	./scripts/test_smoke_stage2_qemu_failures.sh

run: build
	./scripts/run_qemu.sh

run-stage2: stage2
	./scripts/run_stage2_qemu.sh

clean:
	rm -rf build/*.gwo build/stage2-build.* build/generated-fixture.*
