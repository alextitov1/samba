IMAGE ?= 4esnok/samba-container:test
DEBUG_IMAGE ?= 4esnok/samba:debug
PLATFORM ?=

.PHONY: build test config shell debug debug-test debug-shell debug-run

build:
	docker build $(if $(PLATFORM),--platform $(PLATFORM),) -t $(IMAGE) .

test: build
	IMAGE=$(IMAGE) ./tests/integration.sh

config: build
	docker run --rm --entrypoint testparm $(IMAGE) --suppress-prompt

shell: build
	docker run --rm -it --entrypoint /bin/sh $(IMAGE)

publish: build
	docker push $(IMAGE)
# Development image: Samba from the AlmaLinux repositories instead of built
# from source, so the edit/rebuild loop on the entrypoint is ~1s not ~10min.
debug:
	docker build $(if $(PLATFORM),--platform $(PLATFORM),) -f Dockerfile.debug -t $(DEBUG_IMAGE) .

debug-test: debug
	IMAGE=$(DEBUG_IMAGE) ./tests/integration.sh

debug-shell: debug
	docker run --rm -it --entrypoint bash $(DEBUG_IMAGE)

# Run the entrypoint for real with a throwaway share, to poke at it live.
debug-run: debug
	docker run --rm -it -p 4450:445 \
		-e 'SHARE1=data;/shares;yes;no;yes' \
		$(DEBUG_IMAGE)
