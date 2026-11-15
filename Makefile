.PHONY: check test lint release publish install

# This host's default MacOSX27.2 SDK ships a libpthread.tbd the linker
# cannot parse ("unknown architecture"); the 26.5 SDK links cleanly.
# Use it when present; harmless elsewhere.
MAC_SDK := $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then echo /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi)
DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build

check: lint
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
	./test/skills.sh
	$(DUNE_BUILD) src/quest/main.exe
	./test/q.sh
	./test/worktree.sh
	./test/tape.sh
	./test/hooks.sh
	./test/induct.sh
	./test/completion.sh
	./test/release.sh
	./test/install.sh

lint:
	shellcheck bin/bp3 scripts/check-skills test/skills.sh test/q.sh test/worktree.sh test/tape.sh test/hooks.sh test/induct.sh test/completion.sh test/release.sh test/install.sh completions/bp3.bash scripts/release-check scripts/install-bp3.sh scripts/bp3-shim scripts/release-publish
	node --check skills/induct/workflows/induct-exp.js
	node --check skills/induct/workflows/induct-grade.js
	node --check skills/induct/workflows/quest-land.js

test:
	./test/skills.sh

# --- release (Exp 5): tag-gated artifact + checksum; publish-once via gh ---
RELEASE_VERSION := $(shell sed -n 's/.*bp3_version = "\(.*\)".*/\1/p' src/quest/gitx.ml | head -1)
RELEASE_OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
RELEASE_ARCH := $(shell uname -m)
RELEASE_ARTIFACT := dist/bp3-q-v$(RELEASE_VERSION)-$(RELEASE_OS)-$(RELEASE_ARCH)

release:
	@./scripts/release-check >/dev/null
	$(DUNE_BUILD) src/quest/main.exe
	mkdir -p dist
	cp _build/default/src/quest/main.exe $(RELEASE_ARTIFACT)
	cd dist && shasum -a 256 $$(basename $(RELEASE_ARTIFACT)) > $$(basename $(RELEASE_ARTIFACT)).sha256
	@echo "released $(RELEASE_ARTIFACT)"

publish: release
	./scripts/release-publish $(RELEASE_ARTIFACT) $(RELEASE_ARTIFACT).sha256

PREFIX ?= $(HOME)/.local
install:
	PREFIX="$(PREFIX)" ./scripts/install-bp3.sh
