.PHONY: check check-full check-fast check-changed test lint release publish install

# This host's default MacOSX27.2 SDK ships a libpthread.tbd the linker
# cannot parse ("unknown architecture"); the 26.5 SDK links cleanly.
# Use it when present; harmless elsewhere.
MAC_SDK := $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then echo /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi)
DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)
DUNE_TEST = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune test$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)

# Gates (test-pyramid tier.2). Every suite lives in test/suites.tsv,
# tagged unit, fixture or slow; the gates pick tiers, never suites.
#   check       the inner loop: lint, dune test, the unit tier (seconds)
#   check-full  the grade/land gate: check plus the fixture and slow tiers
check: lint
	$(DUNE_BUILD) src/quest/main.exe src/quest/run_suites.exe
	$(DUNE_TEST)
	./scripts/run-suites --tier unit

check-full: check
	./scripts/run-suites --tier fixture,slow

# shellcheck targets are derived (every suite's script, every shell
# script in the repo), never listed: scripts/shell-files
lint:
	shellcheck $$(./scripts/shell-files)
	node --check test/pi-tree.test.mjs
	node --check test/fake-bp3/bp3
	node --check scripts/record-transcripts
	node --check skills/induct/workflows/induct-node.js
	node --check skills/induct/workflows/node-loop.js
	node --check skills/induct/workflows/induct-grade.js
	node --check skills/induct/workflows/induct-land.js

# aliases kept for muscle memory: both are the inner loop
check-fast: check
test: check

# change-scoped: the sweep, check, then the suites whose paths match
check-changed:
	./scripts/check-changed.sh

# --- release (Node 5): tag-gated artifact + checksum; publish-once via gh ---
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
