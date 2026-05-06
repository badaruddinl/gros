.PHONY: build check test policy generated-fixtures gwo-header-fixtures gwo-header-fixture-failures gwo-artifact-inventory gwo-artifact-inventory-failures validate stage2 check-stage2 runtime-abi memory-model near-pointers stage2-data smoke-stage2 run run-stage2 clean

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

generated-fixtures:
	./scripts/check_generated_fixtures.sh

gwo-header-fixtures:
	./scripts/check_gwo_header_fixtures.sh

gwo-header-fixture-failures:
	./scripts/test_gwo_header_fixture_failures.sh

gwo-artifact-inventory:
	./scripts/check_gwo_artifact_inventory.sh

gwo-artifact-inventory-failures:
	./scripts/test_gwo_artifact_inventory_failures.sh

validate: policy generated-fixtures gwo-header-fixtures gwo-header-fixture-failures gwo-artifact-inventory gwo-artifact-inventory-failures test check stage2
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
	./scripts/check_runtime_abi.sh $(STAGE2_BUILD_IMAGE)
	./scripts/check_runtime_abi.sh $(STAGE2_DIST_IMAGE)
	cmp -s $(STAGE2_BUILD_IMAGE) $(STAGE2_DIST_IMAGE)
	@echo "ok: build matches dist artifacts"

stage2:
	./scripts/build_stage2_image.sh

check-stage2: stage2
	./scripts/check_stage2_image.sh --require-ndisasm

runtime-abi: stage2
	./scripts/check_runtime_abi.sh $(STAGE2_BUILD_IMAGE)

memory-model: stage2
	./scripts/check_memory_model.sh $(STAGE2_BUILD_IMAGE)

near-pointers: stage2
	./scripts/check_near_pointers.sh $(STAGE2_BUILD_IMAGE)

stage2-data: stage2
	./scripts/check_stage2_data.sh $(STAGE2_BUILD_IMAGE)

smoke-stage2: stage2
	./scripts/smoke_stage2_qemu.sh --require-qemu

run: build
	./scripts/run_qemu.sh

run-stage2: stage2
	./scripts/run_stage2_qemu.sh

clean:
	rm -rf build/*.gwo build/stage2-build.* build/generated-fixture.*
