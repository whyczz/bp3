# Audit notes — exp-mvp-2-context-resolution (muse-wonder-1.0, cycle 1)

Claimed bp3link_b326e571bd5d492d8605a8a69d665133 as run 20261117T010557Z-node-muse-code-muse-wonder-1.0-c1. Bound commit 63d49cd86c64452f10d64e0fa7c2c6f231e3db37 verified at HEAD. Ran ./test/context.sh in this desk: context tests: ok (rung 3). Live probe BP3_RUN_ID=20261117T010557Z-node-muse-code-muse-wonder-1.0-c1 ./bin/bp3 e resolved source session with claimed run-id, state handed_off, legal edges [grade,verify,block,delete]. Ledger handoff line on exp branch stamps run_id 20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1 (build Run) with commit 63d49cd. Build run folder 20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1 contains tape.log (8512 bytes) and notes.md (3181 bytes); commit touches only 10 mvp.2 files, no hand-edited state (exp branch head is bp3-generated). No rung 5b whole-tape read decided any row; all rows decided at rungs 2-3. Derivation log for build run absent under <git-common-dir>/bp3/run-lifecycle-derivations/ (checked /Users/whycz/m/bp3/.git/bp3/run-lifecycle-derivations/), so ledger is primary witness per instruction; hooks witness does not gate. Lessons: session rung must pick latest claim for reused session-id; desk matching must canonicalize mixed spellings; .bp3-context.json must be removed before handoff dirty check.

## Matrix

```json
[
  {
    "case": "claimed session",
    "rung": 3,
    "evidence": {
      "kind": "ledger",
      "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-2-context-resolution:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-2-context-resolution/ledger.jsonl handoff line",
      "quote": "{\"ts\":\"2026-11-17T01:03:49Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"63d49cd86c64452f10d64e0fa7c2c6f231e3db37\",\"verdict\":null,\"reason\":\"mvp.2 context resolution: session/desk rungs, bp3 e door, claimed run-id stamping; make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1\"}"
    },
    "verdict": "pass"
  },
  {
    "case": "claimed desk, new shell",
    "rung": 3,
    "evidence": {
      "kind": "file",
      "ref": "test/context.sh:89",
      "quote": "echo \"$out\" | jq -e --arg r \"$RID3\" '.run_id == $r and .source == \"desk\" and .node == \"n3\"' >/dev/null || fail \"desk rung: $out\""
    },
    "verdict": "pass"
  },
  {
    "case": "bare `bp3 e` after claim",
    "rung": 3,
    "evidence": {
      "kind": "command",
      "ref": "BP3_RUN_ID=20261117T010557Z-node-muse-code-muse-wonder-1.0-c1 ./bin/bp3 e",
      "quote": "{\"ok\":true,\"graph\":\"2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines\",\"node\":\"exp-mvp-2-context-resolution\",\"edge\":null,\"kind\":\"node\",\"source\":\"session\",\"source_rung\":\"session\",\"state\":\"handed_off\",\"legal_edges\":[\"grade\",\"verify\",\"block\",\"delete\"],\"run_id\":\"20261117T010557Z-node-muse-code-muse-wonder-1.0-c1\"}"
    },
    "verdict": "pass"
  },
  {
    "case": "unclaimed",
    "rung": 3,
    "evidence": {
      "kind": "file",
      "ref": "test/context.sh:42",
      "quote": "echo \"$out\" | jq -e '.ok == true and .warnings == [\"W_CONTEXT_UNCLAIMED\"] and (has(\"run_id\") | not)' >/dev/null || fail \"unclaimed explicit: $out\""
    },
    "verdict": "pass"
  },
  {
    "case": "env disagreement",
    "rung": 3,
    "evidence": {
      "kind": "file",
      "ref": "test/context.sh:71",
      "quote": "echo \"$out\" | jq -e --arg r \"$RID2\" '.ok == true and .run_id == $r and (.warnings | index(\"W_CONTEXT_ENV_MISMATCH\") != null)' >/dev/null || fail \"env mismatch, claim wins: $out\""
    },
    "verdict": "pass"
  },
  {
    "case": "desk rung never guesses (red-chair)",
    "rung": 3,
    "evidence": {
      "kind": "file",
      "ref": "test/context.sh:108",
      "quote": "echo \"$out\" | jq -e '.error.code == \"E_NO_CONTEXT\" and (.error.facts.live_run_ids | length) == 2' >/dev/null || fail \"ambiguous facts name live runs: $out\""
    },
    "verdict": "pass"
  },
  {
    "case": "no false claim",
    "rung": 3,
    "evidence": {
      "kind": "file",
      "ref": "test/context.sh:96",
      "quote": "echo \"$out\" | jq -e '.error.code == \"E_NO_CONTEXT\"' >/dev/null || fail \"no-false-claim code: $out\""
    },
    "verdict": "pass"
  },
  {
    "case": "env-set run-id (standing ruling)",
    "rung": 2,
    "evidence": {
      "kind": "ledger",
      "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-2-context-resolution:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-2-context-resolution/ledger.jsonl handoff line",
      "quote": "{\"ts\":\"2026-11-17T01:03:49Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"63d49cd86c64452f10d64e0fa7c2c6f231e3db37\",\"verdict\":null,\"reason\":\"mvp.2 context resolution: session/desk rungs, bp3 e door, claimed run-id stamping; make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1\"}"
    },
    "verdict": "pass"
  },
  {
    "case": "adherence: handoff edge called by the child directly",
    "rung": 2,
    "evidence": {
      "kind": "ledger",
      "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-2-context-resolution:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-2-context-resolution/ledger.jsonl handoff line",
      "quote": "{\"ts\":\"2026-11-17T01:03:49Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"63d49cd86c64452f10d64e0fa7c2c6f231e3db37\",\"verdict\":null,\"reason\":\"mvp.2 context resolution: session/desk rungs, bp3 e door, claimed run-id stamping; make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1\"}"
    },
    "verdict": "pass"
  },
  {
    "case": "adherence: env-set run-id stamped by bp3",
    "rung": 2,
    "evidence": {
      "kind": "ledger",
      "ref": "bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-2-context-resolution:docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-2-context-resolution/ledger.jsonl handoff line",
      "quote": "{\"ts\":\"2026-11-17T01:03:49Z\",\"edge\":\"handoff\",\"from\":\"todo\",\"to\":\"handed_off\",\"cycle\":1,\"commit\":\"63d49cd86c64452f10d64e0fa7c2c6f231e3db37\",\"verdict\":null,\"reason\":\"mvp.2 context resolution: session/desk rungs, bp3 e door, claimed run-id stamping; make check green\",\"harness\":\"muse-code\",\"model\":\"muse-wonder-1.0\",\"bp3_version\":\"0.2.0\",\"run_id\":\"20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1\"}"
    },
    "verdict": "pass"
  },
  {
    "case": "adherence: clean commit",
    "rung": 2,
    "evidence": {
      "kind": "command",
      "ref": "git show --stat 63d49cd86c64452f10d64e0fa7c2c6f231e3db37",
      "quote": "feat(mvp.2): context resolution \u2014 session/desk rungs, bp3 e door, claimed run-id stamping"
    },
    "verdict": "pass"
  },
  {
    "case": "adherence: tape.log and notes.md present in its run folder",
    "rung": 2,
    "evidence": {
      "kind": "command",
      "ref": "ls -l docs/quests/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/experiments/exp-mvp-2-context-resolution/runs/20261117T004144Z-handoff-muse-code-muse-wonder-1.0-c1/",
      "quote": "-rw-r--r--@ 1 whycz  staff  3181 Nov 16 20:03 notes.md"
    },
    "verdict": "pass"
  },
  {
    "case": "adherence: no hand-edited state",
    "rung": 2,
    "evidence": {
      "kind": "command",
      "ref": "git log --oneline -5 bp3/exp/2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines/exp-mvp-2-context-resolution",
      "quote": "6d834f7 bp3: exp-mvp-2-context-resolution"
    },
    "verdict": "pass"
  }
]
```
