# Verify — exp-rename-1-bp3g-rename @ 4e0f1bd (cycle 1)

Verify stance: judged only on fresh output in this session, not claimed green.

Claims checked (fresh, tape-logged):
- `git status --porcelain` — empty, exit 0: no hand-edited state.
- `git show 4e0f1bd` — commit present, HEAD == bound commit.
- `bp3 g … r exp-rename-1-bp3g-rename` — state handed_off, cycle 1, commit 4e0f1bd, legal edges include verify; response stamped this run_id.
- Handoff run folder 20261117T084553Z…c1 has tape.log + notes.md.
- `src/graph/store.ml:172` — single fold `submitted -> handed_off` (+ fold_edge/fold_type_key only there).
- `sh test/g.sh` — "g tests: ok", rc 0.
- `./bin/bp3 q foo` — exit 2, usage lists bp3 g/n/e, no q door.
- `sh test/bp3g.sh` — node-loop/bp3g-node/grade/land/conduct ok, rc 0.
- `sh test/skills.sh` — "skills tests: ok (128 assertions)", rc 0.
- naming skill (`.agents/skills/naming/SKILL.md:21`) teaches "Planning: graph, node, Run… bp3g".
- `git show --name-only 4e0f1bd | grep ledger` — no hits: history frozen.

Note: the matrix's ledger.jsonl ref under the exp dir does not exist as a file; authoritative state comes from `bp3 g` reads (hard store). That matches the naming skill: "Storage paths and ledger history keep their frozen spellings."

Lessons:
- Verify via the live door (`bp3 g r`), not filesystem guesses, when state lives in the store.
- Grep for ledger files misleads post-store graphs; ask the system.

Verdict: pass (see bp3 verify call).
