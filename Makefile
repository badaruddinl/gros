.PHONY: build check test policy project-policy-failures generated-fixtures generated-fixtures-failures boot-image-failures grscall-registry grscall-registry-failures gwo-header-fixtures gwo-header-fixture-failures gwo-artifact-inventory gwo-artifact-inventory-failures validate stage2 check-stage2 stage2-image-failures runtime-abi runtime-abi-failures memory-model memory-model-failures near-pointers near-pointers-failures stage2-data stage2-data-failures stage2-commands stage2-command-failures stage2-input stage2-input-failures smoke-stage2-failures smoke-stage2 run run-stage2 clean

BUILD_IMAGE := build/gros-v0.5.gwo
DIST_IMAGE := dist/gros-v0.5.gwo
STAGE2_BUILD_IMAGE := build/gros-stage2.gwo
STAGE2_DIST_IMAGE := dist/gros-stage2.gwo

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

generated-fixtures:
	./scripts/check_generated_fixtures.sh

generated-fixtures-failures:
	./scripts/test_generated_fixtures_failures.sh

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

validate: policy project-policy-failures generated-fixtures generated-fixtures-failures boot-image-failures grscall-registry grscall-registry-failures gwo-header-fixtures gwo-header-fixture-failures gwo-artifact-inventory gwo-artifact-inventory-failures runtime-abi-failures stage2-image-failures memory-model-failures stage2-data-failures near-pointers-failures stage2-command-failures stage2-input-failures smoke-stage2-failures test check stage2
	./scripts/check_boot.sh $(DIST_IMAGE)
	./scripts/validate_boot_image.sh --require-ndisasm $(BUILD_IMAGE)
	./scripts/validate_boot_image.sh --require-ndisasm $(DIST_IMAGE)
	cmp -s $(BUILD_IMAGE) $(DIST_IMAGE)
	./scripts/check_stage2_image.sh --require-ndisasm $(STAGE2_BUILD_IMAGE)
	./scripts/check_stage2_image.sh --require-ndisasm $(STAGE2_DIST_IMAGE)
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
	./scripts/check_runtime_abi.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_runtime_abi.sh $(STAGE2_DIST_IMAGE)
	cmp -s $(STAGE2_BUILD_IMAGE) $(STAGE2_DIST_IMAGE)
	@echo "ok: build matches dist artifacts"

stage2:
	./scripts/build_stage2_image.sh

check-stage2: stage2
	./scripts/check_stage2_image.sh --require-ndisasm

stage2-image-failures:
	./scripts/test_stage2_image_failures.sh

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
