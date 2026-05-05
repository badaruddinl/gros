.PHONY: build check test validate run clean

BUILD_IMAGE := build/gros-v0.5.gro
DIST_IMAGE := dist/gros-v0.5.gro

build:
	./scripts/build_boot.sh

check: build
	./scripts/check_boot.sh

test:
	./scripts/test_grraw.sh

validate: test check
	./scripts/check_boot.sh $(DIST_IMAGE)
	./scripts/validate_boot_image.sh $(BUILD_IMAGE)
	cmp -s $(BUILD_IMAGE) $(DIST_IMAGE)
	@echo "ok: build matches dist artifact"

run: build
	./scripts/run_qemu.sh

clean:
	rm -rf build/*.gro
