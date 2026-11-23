---
status: frozen
date: 2026-11-17
promoted: null
---

# Warden — plug-style rules over run evidence (miner, graph 3 of 3)

## Context

Frozen 2026-11-17, third in the miner chain: tape scraper →
SQLite ([2026-11-17-tape-scraper-sqlite.md](2026-11-17-tape-scraper-sqlite.md))
→ profiler/trace
([2026-11-17-run-profiler-chrome-trace.md](2026-11-17-run-profiler-chrome-trace.md))
→ warden. The seed evidence is the child misbehavior catalog
below (nine mechanically detectable rows, four patterns),
copied verbatim 2026-11-17 from the retired
`2026-11-13-session-log-mining.md` (owner cleanup B; that
entry's harness-log half died with it). Owner's framing: act on the profiler, find
the slow/bad paths early, file papercuts — detection is
post-hoc, the warden never writes state and never interrupts
a Run.

## Sketch

Elixir/Phoenix plug pipeline, owner's analogy. One evidence
bundle flows through independent rules; each rule appends
findings or passes. No rule mutates another's input.

```python
# conn = evidence bundle for one (graph, node, cycle) or one run
conn = {sqlite, profile, grade_matrix, commits, tape_refs}
for plug in [refusal_fatigue, verdict_race, model_in_data_plane,
             dropped_context, duration_outlier, dup_test_runs, ...]:
    conn = plug(conn)        # appends findings[]; may tag severity
emit(conn.findings)          # → papercut candidates / followup nodes
```

| Input | Source | Example rule over it |
|---|---|---|
| SQLite (tapes, tool_calls) | graph 1 | same refusal ≥N× per handoff (#6) |
| Profiler trace/rollups | graph 2 | cycle duration/tool-calls ≫ node median (#8) |
| Grader matrix (commit + node record → verdict rows) | live grade | two casts of one edge in one window (#5) |
| Commits/diffs | git | output bytes copied into a return (#1), hand-edited state |
| Tape excerpts (by ref, never copied wholesale) | graph 1 | dispatch arg absent from child prompt (#3) |

Output contract: each finding names rule, evidence ref
(sqlite query / trace interval / ledger line), and severity.
Findings become conductor-filed followup nodes — the warden
proposes, the conductor disposes. Catalog rows #1–#9 are the
first rule set; each shipped fix (validations, context
threading, log-pointer transport) is a regression case.

Deliberately not: no mid-run intervention, no auto-`blocked`,
no LLM judge as a rule — rules are deterministic plugs; an
LLM may *summarize* findings, never mint them.

## Blockers

- **Depends on graphs 1–2.** Rules over raw tape by hand was
  the pre-icebox failure mode; no warden before the DB exists.
- **Thresholds are guesses today** (≥N refusals, ≫ median).
  Tune on the catalog's nine known rows first; a rule that
  cannot reproduce its seed row does not ship.
- **False-positive budget undecided:** how many junk findings
  per real one before the conductor stops reading? Decide
  with the first real report in hand.
- **Catalog is the seed, not the ceiling.** New rows need a
  mechanically detectable signal or they stay anecdotes.

## Promotion trigger

Thaw when graphs 1–2 have landed and a new misbehavior class
burns a cycle that a catalog rule would have caught — or when
the conductor files the third hand-detected papercut of a
kind already in the catalog. First acceptance: warden report
over the graph-engine quest's own runs reproduces ≥ the nine
seed rows.

## Warden evidence: child misbehavior catalog (2026-11-17)

Added from the graph-engine quest
(2026-11-16-bp3-graph-engine-mvp-2-links-dags-pi-muse-engines),
where workflow children misbehaved in repeatable,
mechanically detectable ways. This is the warden's
first concrete training set: not "watch everything",
but score these signals over tapes and run logs
(.git/bp3/<run-id>-log included) and file papercut
candidates. Detection is post-hoc mining; the warden
never writes state and never interrupts a Run.

| # | Misbehavior | Observed evidence | Mechanical signal |
|---|---|---|---|
| 1 | Transport child copied 513-line `git show --stat` verbatim into a JSON return; invalid JSON killed the grade | followup.3 grades x2 `audit_failure`, ~195s child time, zero matrix | child output contains output of a command it just ran; output/input token ratio >> 1 |
| 2 | Read children guessed repo root and ran the old-dialect `./bin/bp3`; whole step refused | bp3g-land attempts 1-2, grade attempt 1 (rename.1) | refusal plus cwd outside the desk in tape |
| 3 | node-loop accepted the `context` arg and never put it in the author brief; fixes arrived by hand-amendment | mvp.3 / followup.1 / dogfood cycles | dispatch arg not a substring of the child prompt |
| 4 | Audit children returned free-text evidence; rows downgraded to `missing` | "row carried no typed evidence" (config.1; mvp.3 reached cycle cap, blocked) | `evidence.kind` absent in returned rows |
| 5 | Grade and verify children raced verdict casts; the second ate `E_ILLEGAL_EDGE` | followup.1 and followup.2 grade returns ("expected verdict race") | two casts of the same edge inside one grade window |
| 6 | `bind-tape E_AMBIGUOUS` after nearly every Muse handoff (4 candidate tapes) | followup.2 defect 3; conductors trained to ignore refusals | same refusal code at least N times per handoff |
| 7 | Workflow reported `refused` when the handoff had actually committed | followup.2 author attempt; conductor verified state by hand | workflow outcome disagrees with a state read |
| 8 | Author ran the full wall-clock `make check` per cycle; no fast tier | followup.3 author: 55 tool calls, ~20 min, 310 files touched | duration / tool-call outlier vs node median |
| 9 | Audit re-ran suites the author had just run, uncached | grade matrices re-quoting `test/skills.sh` executions | same test command in author and audit tapes for one commit |

Four patterns cover the catalog, and they are the
warden's first checklist:

```text
(a) model in the data plane   copying bytes instead of pointing at them  (#1, #9)
(b) received-but-unsaid       arg in the envelope, absent from prompt    (#2, #3)
(c) parallel writers racing   two children, one state edge               (#5)
(d) refusal fatigue           same refusal until it becomes wallpaper    (#6, #7)
```

Fixes shipped mid-quest already validate the
catalog's usefulness: deskNote reads (#2), context
threading (#3), typed-evidence validations (#4),
and log-pointer transport (#1) each killed one row.
The warden's job is to find the next rows before
they burn a cycle.
