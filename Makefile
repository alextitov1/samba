IMAGE ?= 4esnok/samba-container:test
PLATFORM ?=

.PHONY: build test config shell

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