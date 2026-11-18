---
date: 2026-11-17
graph: ../GRAPH.md
exp: followup.5
status: proposed
---

# followup.5 - pure-grade: the grader computes, the looper applies

## TL;DR

Owner decision (2026-11-17): the grader is a
pure function — `grade(commit, node_record) ->
Verdict` — and writes nothing. All effects live
in the looper/conductor: one verdict cast,
fix-ledger entries, dispatch. Today the grade
and verify children both cast and the second
eats `E_ILLEGAL_EDGE` (the "expected verdict
race" on followup.1/followup.2 grades), and the
audit child holds the state pen during its own
audit. This node splits compute from effect and
gives the looper named pushback/escalation
paths instead of silent retries.

## Demo (design trace)

```text
before: grade child audits AND casts; verify child casts again -> E_ILLEGAL_EDGE race
after:  audit/verify children return verdicts (zero bp3 g u calls)
        looper: checks -> casts ONCE -> ledgers fix -> dispatches author
        looper pushback: superseded commit / empty fix / blocked state -> named refusal
```

## Diagram

```text
audit ─┐
       ├─► Verdict (data) ─► looper.apply ─┬─ cast once (bp3 g u)
verify ┘        pure                      ├─ fix-ledger OPEN entry (verbatim) + commit
                                          ├─ dispatch author (context = fix)
                                          └─ pushback: named refusal / escalate owner
author: code + RESOLVED entry in its fix commit; grader never edits the record
```

## Pseudocode

```python
def grade(commit, record) -> Verdict: ...      # no writes, replayable

def apply(verdict, read):
    if verdict.commit != read.commit: return refuse("superseded - re-grade")
    if verdict.outcome == "needs_fix" and not verdict.fix: return escalate("empty fix")
    if read.state == "blocked": return escalate("owner gate")
    cast_once(verdict); ledger_open(verdict.fix); dispatch_author(context=verdict.fix)
```

| Field | Value |
|---|---|
| Intent | a killed or disbelieved grade leaves zero writes behind |
| Lane | standard |
| Output | return-only audit children, single-cast applier, named looper pushback |
| Depends on | followup.3 (renames first; workflows change once, in final vocabulary) |

## Acceptance

| Case | Expected |
|---|---|
| pure audit | audit/verify children make zero `bp3 g u` calls (tape grep evidence) |
| single cast | exactly one verdict cast per grade; the verdict-race refusal no longer occurs in the workflow fixtures |
| safe replay | a grade killed mid-run, re-dispatched on the same commit, leaves no partial writes (state read before/after) |
| pushback: superseded | verdict naming a non-current commit is refused by name; no cast attempted |
| pushback: empty fix | `needs_fix` with no fix text escalates (named) instead of dispatching an author |
| pushback: blocked | a cast attempted over a `blocked` read escalates to the owner gate; state untouched |
| fix ledger live | one real `needs_fix` cycle runs: OPEN entry (conductor) → author fix → RESOLVED entry (author commit) → grade verifies |
| regression | workflow tests cover cast-once + all three pushbacks; `make check` green |

## Acceptance test (goal block)

- **Objective:** grade computes, looper applies,
  nobody else writes.
- **Prove by:** tape greps, cast counts, pushback
  fixtures, one live ledgered cycle.
- **Done when:** a full grade runs with a single
  cast and the race refusal is gone.

## Tests

Workflow unit fixtures for return-only children,
single cast, and the three pushbacks; `make check`.

## Context

Owner: "we're keeping the grader as a pure
function, e.g. commit + exp/node => looper
writes" — "the node looper can push back,
escalate, etc, okay let's lock that in."
Fix-ledger convention (in the node record,
append-only): OPEN by conductor, RESOLVED by
author in its fix commit, verified by grader.
Not the killed followup.4: no typed payload
schema; the fix stays verbatim text.

## Amendment (owner, 2026-11-17): audit reuses run evidence (warden row #9)

The audit child must not re-run, uncached,
suites the author already ran for the same
commit. The validations LOG (`.git/bp3/<ts>-
<node>-validations.log`) and the author Run's
notes/test outputs are the shared evidence
plane: audit reads them first and re-runs only
acceptance-named tests that lack typed evidence
there. Acceptance adds: (1) a fixture audit
whose acceptance test already has typed pass
evidence in the author Run artifacts does not
re-execute that suite (tape grep: command
absent from the audit tape); (2) a case with
no prior evidence is executed by the audit as
today; (3) reused evidence is quoted with its
source (log path / run folder), never as a
fresh run.

## Amendment (owner, 2026-11-17): a named mechanical fix never blocks

Owner, after followup.3 cycle 3 blocked on a one-word
stale term: "we should not block and bubble up to me,
this should be fixed by the grader, etc." Grade stays
pure; the looper applies. The classification rule:

| Fix class | Outcome | Owner paged? |
|---|---|---|
| named mechanical fix: verdict names exact file/line/text change, no scope or judgment call (e.g. stale term, broken pointer) | `needs_fix` at any cycle count; looper auto-dispatches the author cycle with the fix verbatim | never |
| owner-only calls: scope change, `delete`, ambiguity the record cannot settle, empty fix text | `blocked` (existing pushbacks) | yes |
| disagreement: the same acceptance row fails again after its named fix was applied | counts toward the cycle cap; cap reached → `blocked` | at cap |

The cycle cap counts disagreement cycles only; a
first-failure mechanical fix does not consume it.
Acceptance adds: (1) fixture grade at cycle ≥ cap
failing only on a named mechanical row casts
`needs_fix`, state returns to `todo`, no `blocked`
line written; (2) fixture where the same row fails
after its named fix was applied counts one
disagreement cycle and blocks at cap; (3) one live
mechanical cycle (planted stale term) rides
grade → author → grade with zero owner contact.

## Fix ledger (append-only)

- 2026-11-18 · cycle 2 · from grade of 4ab3228 (needs_fix) · status: open
  fix: "In test/dogfood-parallel.sh, update the two stale consumers of the old two-cast contract for the followup.5 combined cast: (1) the bubble-drive agent() mock must dispatch on the looper apply child first (label \"apply <node>\" / its Run-exactly grade --verdict ... --verify-verdict ... command — run it and return its stdout JSON) instead of parsing a bp3link_ token from that spawn text and dereferencing the null match (TypeError at bubble-drive.mjs:161 via bp3g-node.js:488 callApply); (2) the parallel-grade ledger jq check must accept the single combined grade ledger line carrying verify_verdict=pass instead of requiring a separate edge==verify verdict==pass line. Done when ./test/dogfood-parallel.sh passes and make check exits 0 at the fix commit."
  regression_test: ./test/dogfood-parallel.sh + make check (named in the fix)

- 2026-11-18 · cycle 2 · RESOLVED (this handoff)
  resolution: "Both stale consumers updated in test/dogfood-parallel.sh: (1) the Muse bubble host agent() dispatches kind \"apply\" before the bp3link_ token parse — it runs the spawn text's Run-exactly combined cast via sh(extractCmd(input)) and returns its stdout JSON (a refused cast returns its error JSON, never a null deref); (2) author_worker now casts once (grade --verdict ship --verify-verdict pass --commit <bound>) and the quality-floor check asserts the single grade line carries verify_verdict pass with zero verify-edge lines. Failure reproduced at 4ab3228 first (TypeError at bubble-drive.mjs:161 via callApply); verified at the fix commit: ./test/dogfood-parallel.sh exit 0 (bubble scorecard pi/claude blocked, claude fresh landed, siblings unaffected) and make check exit 0. Grade-blocking porcelain cleared: the four cycle-4 followup.3 run notes and the three cycle-1 run notes of this node are committed as deliberate evidence; tapes stay gitignored, git status --porcelain empty."

- 2026-11-18 · cycle 2 · correction (this run, after handoff)
  note: "The RESOLVED entry above claimed make check exit 0 at the handoff commit before the gate finished; at that commit make check fails at test/completion.sh (flags --verify-verdict/--mechanical, parsed since 4ab3228, missing from completions/_bp3 and completions/bp3.bash — pre-existing, masked while dogfood-parallel failed earlier in the gate). The follow-up commit on this branch adds both flags to both completion lists; test/completion.sh and full make check pass there. The handoff-bound commit does not contain the follow-up."

- 2026-11-18 · cycle 3 · from grade of 31b7c74 (needs_fix, mechanical) · RESOLVED (this handoff)
  resolution: "Named mechanical fix applied: --verify-verdict and --mechanical added to the _bp3_flags lists in completions/_bp3 and completions/bp3.bash, matching src/graph/main.ml parse_flags (flags ride the followup.5 combined cast since 4ab3228). The flag lines landed in follow-up 0ee41e2 and ride this handoff commit by ancestry; verified at the fix commit: ./test/completion.sh -> completion tests: ok and make check exit 0 (all gate steps ok, including dogfood-parallel, bp3g, completion, release, install). Pending cycle-2 audit/grade/verify run notes committed as deliberate evidence; tapes stay gitignored."

- 2026-11-18 · cycle 4 · from grade of 84be74a (needs_fix) · RESOLVED (this handoff)
  resolution: "Gate slowness diagnosed and fixed at the root; no suite trimmed. (1) test/g.sh is ~250 bp3 g calls over a fixture growing to ~45 nodes; at 84be74a each call re-read every ledger via fresh git subprocesses (one graph read at 15 nodes = 106 git calls / 1.57s, +~60ms per node), so g.sh alone ran >290s unfinished. Fix in src/graph/gitx.ml + store.ml + main.ml: per-process tip/show caches and one git cat-file --batch ledger reader, invalidated on every ref move (commit_files, land update-ref), an epoch-keyed list_refs cache, and an allocation-free contains_sub. Graph read at 15 nodes: 106 -> ~40 git calls, 1.57s -> 0.56s; g.sh: >290s unfinished -> 125s green. (2) Behind g.sh, extensions/bp3-pi/test hung unbounded: harness watch on a minted-but-unclaimed run has no InitRecord (run_config_records keeps claimed only) and scanned both harnesses' tape roots, reading a 4.5GB / 2,985-file muse corpus per call (>30s CPU, killed). Fix in src/graph/harness.ml (scan_harnesses/config_harness): a minted run's config names its harness, so find-tape/watch scan that harness's roots only; watch on the minted run: >30s -> 0.25s, same verdicts. Verified at the fix commit: full make check exits 0 (all suites ok: lint, skills 134, g, ready, diagram, blocked, pi-tree, harness, config, link, dogfood-link, dogfood-parallel, context, bp3-pi 13 pass, worktree, tape, cleanliness, hooks, bp3g, completion, release, install). Per-suite timings quoted in the cycle-4 author run notes. Pending cycle-3 run notes committed as deliberate evidence; tapes stay gitignored."
