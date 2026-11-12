.PHONY: check test lint

check: lint
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
	./test/skills.sh
	dune build invoke/main.exe
	./test/q.sh
	./test/tape.sh

lint:
	shellcheck bin/bp3 scripts/check-skills test/skills.sh test/q.sh test/tape.sh

test:
	./test/skills.sh
