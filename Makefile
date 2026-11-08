.PHONY: check test lint

check: lint
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
	./test/skills.sh
	dune build invoke/main.exe
	./test/invoke.sh

lint:
	shellcheck bin/bp3 scripts/check-skills test/skills.sh test/invoke.sh

test:
	./test/skills.sh
