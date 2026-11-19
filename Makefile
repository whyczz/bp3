.PHONY: check check-full check-fast check-changed test lint ocaml release publish install

# This host's default MacOSX27.2 SDK ships a libpthread.tbd the linker
# cannot parse ("unknown architecture"); the 26.5 SDK links cleanly.
# Use it when present; harmless elsewhere.
MAC_SDK := $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then echo /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi)
DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)
DUNE_TEST = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune test$(if $(findstring /.bp3/worktrees/,$(CURDIR)), --root=.,)

# Gates (test-pyramid tier.2). Every suite lives in test/suites.tsv,
# tagged unit, fixture or slow; the gates pick tiers, never suites.
#   check       the inner loop: lint, dune test, the unit tier (seconds)
#   check-full  the grade/land gate: lint, dune test, every tier
# check-full runs every tier itself, not through check. lint's
# check-gates pins both plans exactly (an allowlist: check-full is check
# with every tier) and refuses ignore-errors anywhere in this file.
# Changing a gate means changing scripts/check-gates too.
check: lint ocaml
	./scripts/run-suites --tier unit

check-full: lint ocaml
	./scripts/run-suites

# both binaries, then the OCaml unit tests
ocaml:
	$(DUNE_BUILD) src/quest/main.exe src/quest/run_suites.exe
	$(DUNE_TEST)

# lint's targets are derived, never listed: scripts/shell-files names
# every shell script (shellcheck) and every JS file (node --check)
lint:
	./scripts/check-gates
	files=$$(./scripts/shell-files) && [ -n "$$files" ] && shellcheck $$files
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
	files=$$(./scripts/shell-files --node) && [ -n "$$files" ] && for f in $$files; do node --check "$$f" || exit 1; done

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
