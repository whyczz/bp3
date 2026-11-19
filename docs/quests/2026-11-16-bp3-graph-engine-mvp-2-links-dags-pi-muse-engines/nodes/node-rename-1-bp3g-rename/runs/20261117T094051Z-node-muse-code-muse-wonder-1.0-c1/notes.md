# Audit notes — exp-rename-1-bp3g-rename @ 4e0f1bd0d90f13a12623012b5628f7c38165577c

Lessons: (1) The fold is genuinely single-sited — `fold_edge`/`fold_state_name` in `src/graph/store.ml` carry the whole old-to-new compat mapping and `submitted` appears nowhere else in `src/graph/`. (2) `bp3 q` refusal is a generic usage + exit 2, not an explicit "unknown door" message; behavior matches the spec, wording does not. (3) Remaining live `quest` hits are frozen storage paths (`docs/quests/`) plus prose, which the naming skill explicitly carves out — vocabulary-zero means identifier-zero. (4) `test/bp3g.sh` conduct coverage is a mock-host contract test, not a live agent drive; the smoke-drive clause rests on that mock plus `skills.sh` renders. Matrix decided at rungs 2-3; no whole-tape (rung 5b) reads; no derivation log existed for this run_id at audit time (`/Users/whycz/m/bp3/.git/bp3/run-lifecycle-derivations/` has older runs only).

## Matrix (verbatim JSON)

[
{"case": "verbs already migrated", "rung": 2, "evidence": {"kind": "command", "ref": "grep -rn submitted src/graph/ + sed store.ml fold region in worktree at 4e0f1bd", "quote": "src/graph/store.ml:172:let fold_state_name = function \"submitted\" -> \"handed_off\" | s -> s"}, "verdict": "pass"},
{"case": "bp3 g is the door", "rung": 3, "evidence": {"kind": "command", "ref": "sh test/g.sh", "quote": "g tests: ok"}, "verdict": "pass"},
{"case": "old door gone", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 q foo > /tmp/bp3q.out 2>&1; echo exit=$?", "quote": "exit=2"}, "verdict": "pass"},
{"case": "bp3g skills conduct", "rung": 3, "evidence": {"kind": "command", "ref": "sh test/bp3g.sh", "quote": "bp3g-conduct tests: ok"}, "verdict": "pass"},
{"case": "vocabulary zero", "rung": 3, "evidence": {"kind": "command", "ref": "sh test/skills.sh", "quote": "skills tests: ok (128 assertions)"}, "verdict": "pass"},
{"case": "naming skill updated", "rung": 2, "evidence": {"kind": "file", "ref": "skills/naming/SKILL.md vocabulary section", "quote": "- Planning: graph, node, Run. The conducting skill family is"}, "verdict": "pass"},
{"case": "history frozen", "rung": 2, "evidence": {"kind": "command", "ref": "git show --name-only --format= 4e0f1bd0d90f13a12623012b5628f7c38165577c | grep ledger", "quote": "(no ledger paths)"}, "verdict": "pass"}
]
