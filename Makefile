.PHONY: build check test validate stage2 check-stage2 smoke-stage2 run run-stage2 clean

BUILD_IMAGE := build/gros-v0.5.gro
DIST_IMAGE := dist/gros-v0.5.gro
STAGE2_BUILD_IMAGE := build/gros-stage2.gro
STAGE2_DIST_IMAGE := dist/gros-stage2.gro

build:
	./scripts/build_boot.sh

check: build
	./scripts/check_boot.sh

test:
	./scripts/test_grraw.sh

validate: test check check-stage2
	./scripts/check_boot.sh $(DIST_IMAGE)
	./scripts/validate_boot_image.sh $(BUILD_IMAGE)
	cmp -s $(BUILD_IMAGE) $(DIST_IMAGE)
	./scripts/check_stage2_image.sh $(STAGE2_DIST_IMAGE)
	cmp -s $(STAGE2_BUILD_IMAGE) $(STAGE2_DIST_IMAGE)
	@echo "ok: build matches dist artifacts"

stage2:
	./scripts/build_stage2_image.sh

check-stage2: stage2
	./scripts/check_stage2_image.sh

smoke-stage2: stage2
	./scripts/smoke_stage2_qemu.sh

run: build
	./scripts/run_qemu.sh

run-stage2: stage2
	./scripts/run_stage2_qemu.sh

clean:
	rm -rf build/*.gro build/stage2-build.*
