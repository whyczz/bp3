.PHONY: check check-full check-fast check-changed test lint ocaml release publish install

# This host's default MacOSX27.2 SDK ships a libpthread.tbd the linker
# cannot parse ("unknown architecture"); the 26.5 SDK links cleanly.
# Use it when present; harmless elsewhere.
MAC_SDK := $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then echo /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi)
DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build
DUNE_TEST = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune test

# Gates (test-pyramid tier.2). Every suite lives in test/suites.tsv,
# tagged unit, fixture or slow; the gates pick tiers, never suites.
#   check       the inner loop: lint, dune build, dune test (seconds)
#   check-full  the grade/land gate: check, plus every suite in suites.tsv
# check-full runs every tier itself, not through check. lint's
# check-gates pins both plans exactly (an allowlist: check-full is check
# plus every suite) and refuses ignore-errors anywhere in this file.
# Changing a gate means changing scripts/check-gates too.
check: lint ocaml

check-full: lint ocaml
	./scripts/run-suites

# both binaries, then the OCaml unit tests
ocaml:
	$(DUNE_BUILD) src/quest/main.exe src/quest/run_suites.exe
	$(DUNE_TEST)

# lint's targets are derived, never listed: scripts/shell-files names
# every shell script (shellcheck)
lint:
	./scripts/check-gates
	./scripts/check-constraints
	./scripts/check-bump
	files=$$(./scripts/shell-files) && [ -n "$$files" ] && shellcheck $$files
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills

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
