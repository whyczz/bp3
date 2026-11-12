.PHONY: check test lint

# This host's default MacOSX27.2 SDK ships a libpthread.tbd the linker
# cannot parse ("unknown architecture"); the 26.5 SDK links cleanly.
# Use it when present; harmless elsewhere.
MAC_SDK := $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then echo /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi)
DUNE_BUILD = $(if $(MAC_SDK),SDKROOT=$(MAC_SDK) ,)dune build

check: lint
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
	./test/skills.sh
	$(DUNE_BUILD) q/main.exe
	./test/q.sh
	./test/tape.sh

lint:
	shellcheck bin/bp3 scripts/check-skills test/skills.sh test/q.sh test/tape.sh

test:
	./test/skills.sh
