.PHONY: check check-fast check-changed test lint release publish install

# This host's default MacOSX27.2 SDK ships a libpthread.tbd the linker
# cannot parse ("unknown architecture"); the 26.5 SDK links cleanly.
# Use it when present; harmless elsewhere.
MAC_SDK := $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then echo /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi)
DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)

check: lint
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
	./test/skills.sh
	$(DUNE_BUILD) src/graph/main.exe
	./test/g.sh
	./test/ready.sh
	./test/diagram.sh
	./test/blocked.sh
	node test/pi-tree.test.mjs
	./test/harness.sh
	./test/config.sh
	./test/link.sh
	./test/dogfood-link.sh
	./test/dogfood-parallel.sh
	./test/context.sh
	node --test extensions/bp3-pi/test/bp3-pi.test.mjs
	./test/worktree.sh
	./test/tape.sh
	./test/cleanliness.sh
	./test/hooks.sh
	./test/bp3g.sh
	./test/completion.sh
	./test/release.sh
	./test/install.sh

lint:
	shellcheck bin/bp3 scripts/check-skills test/skills.sh test/g.sh test/ready.sh test/diagram.sh test/blocked.sh test/harness.sh test/config.sh test/link.sh test/dogfood-link.sh test/dogfood-parallel.sh test/context.sh test/worktree.sh test/tape.sh test/cleanliness.sh test/hooks.sh test/bp3g.sh test/completion.sh test/release.sh test/install.sh completions/bp3.bash scripts/release-check scripts/install-bp3.sh scripts/bp3-shim scripts/release-publish
	node --check test/pi-tree.test.mjs
	node --check skills/bp3g/workflows/bp3g-node.js
	node --check skills/bp3g/workflows/node-loop.js
	node --check skills/bp3g/workflows/bp3g-grade.js
	node --check skills/bp3g/workflows/bp3g-land.js

test:
	./test/skills.sh

# --- check tiers (node-followup-6-check-tiers): per-cycle fast and
# change-scoped verification. Full `check` above is unchanged and
# stays the grade/land gate. Suite table: scripts/check-changed.sh.
check-fast:
	./scripts/check-changed.sh --fast

check-changed:
	./scripts/check-changed.sh

# --- release (Node 5): tag-gated artifact + checksum; publish-once via gh ---
RELEASE_VERSION := $(shell sed -n 's/.*bp3_version = "\(.*\)".*/\1/p' src/graph/gitx.ml | head -1)
RELEASE_OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
RELEASE_ARCH := $(shell uname -m)
RELEASE_ARTIFACT := dist/bp3-g-v$(RELEASE_VERSION)-$(RELEASE_OS)-$(RELEASE_ARCH)

release:
	@./scripts/release-check >/dev/null
	$(DUNE_BUILD) src/graph/main.exe
	mkdir -p dist
	cp _build/default/src/graph/main.exe $(RELEASE_ARTIFACT)
	cd dist && shasum -a 256 $$(basename $(RELEASE_ARTIFACT)) > $$(basename $(RELEASE_ARTIFACT)).sha256
	@echo "released $(RELEASE_ARTIFACT)"

publish: release
	./scripts/release-publish $(RELEASE_ARTIFACT) $(RELEASE_ARTIFACT).sha256

PREFIX ?= $(HOME)/.local
install:
	PREFIX="$(PREFIX)" ./scripts/install-bp3.sh
