# Audit lessons — node-followup-3-goal-term-purge @ 2dbe30c (run 20261117T235455Z-node-muse-code-muse-wonder-1.0-c4)

- Claimed link bp3link_7f16f730e19ebfe611a8a82e7722a75f; returned run_id matched the expected folder name. Run folder did not pre-exist.
- Cycle-5 fix verified at rung 2: at bound commit 2dbe30c, skills/naming Artifacts lists GRAPH.md, using-bp3/CLAUDE.md/AGENTS.md all say GRAPH.md, and live-surface GOAL.md grep hits remain only in the exempt migration rename table.
- Scoped quest grep-zero holds at the bound commit: remaining hits are exactly the named exemptions (src/graph/store.ml legacy fold, migration rename table, naming frozen-spelling note). GRAPH.md carries zero `experiments/` refs and all 18 record links resolve (ok=18 bad=0).
- Rung 3 observed green: `bp3 skills check` fresh, check-skills 40 files, test/skills.sh 134 assertions, node --check grade.js clean, migration dry-run idempotent no-op, and post-purge conduct reads back `handed_off` at the bound commit under the new node ID with zero rename-caused refusals. Full `make check` was started but produced no output within ~6 minutes (tail-buffered) and was terminated; the bound diff touches only Markdown/workflow text, so the fast skills subset covers its blast radius — recorded here rather than claimed as a full-suite pass.
- No rung 5 was needed: every row decided at rungs 2–3, zero whole-tape reads. HEAD sits one commit past the bound commit (followup.5/6 amendments); all file evidence was read at the bound commit via `git show`/`git grep`.

## Evidence matrix

```json
[
  {"case": "files renamed", "rung": 2, "evidence": {"kind": "command", "ref": "link existence sweep over GRAPH.md record links (bound commit 2dbe30c)", "quote": "links ok=18 bad=0"}, "verdict": "pass"},
  {"case": "code renamed", "rung": 3, "evidence": {"kind": "command", "ref": "./scripts/check-skills skills .pi/skills .agents/skills .claude/skills (make check fast subset; full make terminated unobserved)", "quote": "skills check: ok (40 files)"}, "verdict": "pass"},
  {"case": "skills renamed", "rung": 3, "evidence": {"kind": "command", "ref": "./bin/bp3 skills check", "quote": "{\"ok\":true,\"fresh\":[\"node-loop\",\"bp3g-grade\",\"bp3g-land\",\"bp3g-node\"]}"}, "verdict": "pass"},
  {"case": "grep proof", "rung": 2, "evidence": {"kind": "command", "ref": "git grep -niw quest 2dbe30c -- src/ bin/ scripts/ extensions/ skills/ (exempt-only hits)", "quote": "src/graph/store.ml:295:    [\"refs/heads/bp3/graph/\"; \"refs/heads/bp3/goal/\"; \"refs/heads/bp3/quest/\"])"}, "verdict": "pass"},
  {"case": "conduct survives", "rung": 3, "evidence": {"kind": "command", "ref": "BP3_RUN_ID=20261117T235455Z-node-muse-code-muse-wonder-1.0-c4 ./bin/bp3 g 2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines n node-followup-3-goal-term-purge r", "quote": "\"state\":\"handed_off\",\"cycle\":4,\"commit\":\"2dbe30ce32632b9460ab869650d9e5edfb0554c0\""}, "verdict": "pass"},
  {"case": "terms synced", "rung": 2, "evidence": {"kind": "file", "ref": "skills/naming/SKILL.md (bound commit 2dbe30c)", "quote": "- Artifacts: GRAPH.md, state.yaml, ledger.jsonl,"}, "verdict": "pass"},
  {"case": "migration script (Amendment scope C)", "rung": 3, "evidence": {"kind": "command", "ref": "bash scripts/migrate-graph-rename.sh --dry-run", "quote": "migrate-graph-rename: dry-run complete (idempotent: re-run is a no-op)"}, "verdict": "pass"}
]
```
