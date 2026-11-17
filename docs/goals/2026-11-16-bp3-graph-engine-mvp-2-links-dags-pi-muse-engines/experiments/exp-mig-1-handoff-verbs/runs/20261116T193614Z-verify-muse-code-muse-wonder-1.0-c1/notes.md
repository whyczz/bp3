# Verify notes — exp-mig-1-handoff-verbs c1

Verdict decided at rungs 1–3; no whole-tape read needed.

Claims checked (fresh output):
- old quest reads identically — `./bin/bp3 q 2026-11-14-bp3-workflows-v2 r` — exp-1-induct-grade landed/exp_fin/c1/b415f4a3 present. PASS
- new verbs round-trip — `make check` — `q tests: ok`. PASS
- compat in one place — `grep fold_edge/fold_state_name src/quest/store.ml` — lines 156–160, submit→handoff, review→grade, check→verify, submitted→handed_off. PASS
- conducting surfaces updated — `make check` — `skills tests: ok (115 assertions)`, MAKE_EXIT:0. PASS
- this quest survives itself — `./bin/bp3 q ... r exp-mig-1-handoff-verbs` — handed_off/c1/44196725/legal [grade,verify,block,delete]. PASS
- adherence handoff edge — ledger on exp branch via `git show bp3/exp/.../ledger.jsonl` — handoff line ts 19:34:49Z with run_id 20261116T191513Z-submit-...-c1. PASS
- adherence env run-id — same ledger line corroborated by run-lifecycle-derivations init_record. PASS
- adherence clean commit — `git status --short` empty; HEAD 44196725 feat(mig.1). PASS
- adherence tape/notes in build run — notes.md + tape.log (339 lines) present. PASS
- adherence no hand-edited state — `git diff HEAD~1 HEAD | grep -c docs/quests` = 0; induct render diff only GENERATED header. PASS

Lesson: ledger lives on the exp git branch, not the worktree filesystem — read it with `git show bp3/exp/<quest>/<exp>:<ledger path>`.
