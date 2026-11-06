.PHONY: check test lint core-check format-check

check: lint core-check format-check
	./scripts/check-skills skills .pi/skills .agents/skills .claude/skills
	./test/skills.sh

lint:
	shellcheck bin/bp3 bin/bp3-zellij-init scripts/check-skills test/skills.sh tests/materialize-toy tests/start-toy

test: core-check
	./test/skills.sh

core-check:
	dune build @all
	dune runtest
	node --check tests/controller-recovery.mjs
	node --test tests/bridge.test.mjs tests/workspace.test.mjs tests/docs.test.mjs

format-check:
	find core tests -type f \( -name '*.ml' -o -name '*.mli' \) -not -path '*/toy-template/*' -exec ocamlformat --check {} +
