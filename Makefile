#!/usr/bin/make -f

SHELL := /bin/bash
IMG_NAME := dovecot
IMG_REPO := nforceroh
IMG_NS := homelab
IMG_REG := harbor.k3s.nf.lab
DATE_VERSION := $(shell date +"v%Y%m%d%H%M" )
BRANCH := $(shell git rev-parse --abbrev-ref HEAD)
DOCKERCMD := docker

ifeq ($(BRANCH),main)
	VERSION := dev
else
	VERSION := $(BRANCH)
endif

.PHONY: all build push gitcommit gitpush create test
all: build push 
git: gitcommit gitpush 

test:
	@echo "Running image tests for $(IMG_REPO)/$(IMG_NAME):$(VERSION)"
	./tests/run_tests.sh $(IMG_REPO)/$(IMG_NAME):$(VERSION)

build: 
	@echo "Building $(IMG_NAME):$(VERSION) image"
	$(DOCKERCMD) build \
		--build-arg BUILD_DATE="$(shell date -u +'%Y-%m-%dT%H:%M:%SZ')" \
		--build-arg VERSION="$(VERSION)" \
		--build-arg VCS_REF="$(shell git rev-parse --short HEAD)" \
		--tag $(IMG_REPO)/$(IMG_NAME):$(VERSION) \
		--tag $(IMG_REPO)/$(IMG_NAME):latest .

gitcommit:
	@echo "Committing changes"
	git add -A
	git commit -m "chore: build $(VERSION)" || true

gitpush:
	@echo "Pushing $(VERSION) to origin"
	git tag -a $(VERSION) -m "Release $(VERSION)" 2>/dev/null || true
	git push origin main
	git push origin $(VERSION) || true

push: 
	@echo "Pushing $(IMG_NAME):$(VERSION) image"
ifeq ($(VERSION), dev)
	@echo "Pushing to docker.io/$(IMG_REPO)/$(IMG_NAME):dev and :latest"
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME):$(VERSION) docker.io/$(IMG_REPO)/$(IMG_NAME):dev
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME):$(VERSION) docker.io/$(IMG_REPO)/$(IMG_NAME):latest
	$(DOCKERCMD) push docker.io/$(IMG_REPO)/$(IMG_NAME):dev
	$(DOCKERCMD) push docker.io/$(IMG_REPO)/$(IMG_NAME):latest
else
	@echo "Pushing versioned release $(DATE_VERSION) to registries"
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME):$(VERSION) docker.io/$(IMG_REPO)/$(IMG_NAME):$(DATE_VERSION)
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME):$(VERSION) docker.io/$(IMG_REPO)/$(IMG_NAME):latest
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME):$(VERSION) $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):$(DATE_VERSION)
	$(DOCKERCMD) tag $(IMG_REPO)/$(IMG_NAME):$(VERSION) $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):latest
	$(DOCKERCMD) push docker.io/$(IMG_REPO)/$(IMG_NAME):$(DATE_VERSION)
	$(DOCKERCMD) push docker.io/$(IMG_REPO)/$(IMG_NAME):latest
	$(DOCKERCMD) push $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):$(DATE_VERSION)
	$(DOCKERCMD) push $(IMG_REG)/$(IMG_NS)/$(IMG_NAME):latest
endif

end:
	@echo "Done!"