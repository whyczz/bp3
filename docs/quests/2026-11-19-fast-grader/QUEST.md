---
status: canceled
home_repo: bp3
date: 2026-11-19
---

# fast-grader: minutes per grade, evidence by script

Canceled (owner, 2026-11-23: superseded by landed quest
`docs/quests/2026-11-23-fast-agy-induct/`, which kept graders strictly
read-only and promoted `docs/icebox/2026-11-19-fast-grader.md`). On hold
(owner, 2026-11-19: "okay put the fast-grade on hold"). Draft
only, not approved; the icebox entry stays frozen. CONTEXT.md moved to
the constraints-context quest
(`docs/quests/2026-11-19-constraints-context/`).

TL;DR
A node's loop becomes: commit, `scripts/receipt`, hand off, one
narrow grade of about five minutes, land. Two scripts make the
evidence (red-first: the tests fail on the parent's code; receipt:
the gate's exit codes, printed). The grader runs three jobs, may
reject only for a failing acceptance row or a proven bug, and writes
the fix itself when it rejects.

ELI5
Last quest, every change waited about eleven minutes for a reviewer,
and most reviews sent it back for things a script could have caught
in seconds. Now scripts catch those things before the reviewer looks,
the reviewer gets a short checklist instead of an open-ended hunt,
and when the reviewer finds a real bug, the reviewer fixes it instead
of sending it back.

## Context

Promoted from `docs/icebox/2026-11-19-fast-grader.md` (trigger fired:
the owner framed the next induct-loop quest on 2026-11-19), copied
verbatim to [ICEBOX.md](ICEBOX.md).

Measured on test-pyramid (`docs/quests/2026-11-18-test-pyramid/`,
grader subagent transcripts and `bp3 q r` timings):

| What | Number |
|---|---|
| grades | 25, 16 of them re-grades |
| grade wall time | median about 11 min (4-37), 78k-198k tokens of context each |
| tier.1 | 7 cycles, 14.3h wall, 9.4h of it in `handed_off` |
| findings | about half: tests that could not fail, or claims beyond the evidence |
| spec and messages | 1,508 lines of QUEST and NODE records; 53-77 line commit messages on 42-135 line diffs |

Settled with the owner on 2026-11-19 (red chair in session, owner's
words in quotes):

1. Keep a per-node grader, narrow and blocking: "but doesnt take 10 min".
2. `needs_fix` only for a failing acceptance row or a real bug in the diff.
3. On `needs_fix` the grader writes the fix: "can the grader apply the
   fix". No parallel fix branch merged back; parallelism only across
   independent nodes.
4. No hand-written mutant patches: "this is a waste of tokens no?
   we're building deterministic systems?". The parent commit is the
   mutant (red-first).
5. Handoff evidence is printed by a script, not written by the author.
6. Fact-check against other agent systems: "let's fact check with
   other llm agent systems". Done during framing; the ground lands in
   CONTEXT.md through the constraints-context quest.

Measured during framing: a fresh tree of this repo builds in 1.1s and
runs `dune test` in 0.9s (dune cache), so a parent worktree is cheap.

## Terms

- **receipt**: the lines `scripts/receipt` prints for a clean HEAD
  (sha, `make check-full` exit code and summary, red-first line); it is
  the handoff `--reason`.
- **red-first**: `scripts/red-first`, which runs a commit's changed
  tests against its parent's code and expects red (`refactor:` expects
  green).
- **narrow grade**: the grader's three jobs: re-run the receipt, one
  check the author missed, the commit's claims against the evidence.
- **role swap**: on `needs_fix` the grader commits the fix and the
  author grades that commit.
- **follow-up**: a grader finding outside the two `needs_fix` grounds;
  listed in the grade reason, never blocks.
- **incomplete**: a grade where a job could not run; no verdict is cast.
- `needs_fix`, `ship`, `handoff`, `grade`, `land`, `max_cycles`: engine
  spellings, unchanged.

## Inputs

| Input | Source |
|---|---|
| a commit sha | the author's commit, default HEAD |
| the commit's subject type | conventional prefix (`feat`, `fix`, `refactor`, `test`, `docs`, `chore`) |
| changed paths | `git diff --name-only <sha>^ <sha>` |
| the suite table | `test/suites.tsv`, through the parent's `scripts/check-changed.sh` |
| the node's acceptance | NODE.md goal block |

## Outputs

| Output | Shape |
|---|---|
| red-first line | `red-first: red (<step>)` \| `green (refactor)` \| `n/a (<why>)` \| `FAIL <why>`; exit 0, 0, 0, 1; usage 2 |
| receipt | three lines, exit 0 iff gate green and red-first not FAIL; dirty tree 2 |
| grade outcome | `ship` \| `needs_fix` (+ fix sha, + receipt) \| `incomplete`; plus follow-ups |

## Acceptance gates (design trace)

```text
author:  verify.1 commit -> ./scripts/receipt
         receipt 3f2a.. feat(test): red-first ...
         check-full rc=0 run-suites: ok 27/27 wall 37.0s
         red-first red (red-first)
         e handoff --commit 3f2a.. --reason "<receipt>"
grader:  job 1 same receipt; job 2 "deleted test file" -> probe green, real bug
         -> needs_fix, fix 9c1d.. + test; receipt rc 0          (4 min)
author:  e grade needs_fix (grader's reason) ; e handoff 9c1d..
         grades 9c1d.. (3 jobs) -> ship ; e land
bp3 q r: verify.1 landed, cycle 2, handed_off dwell ~4 min per grade
```

Proved by each node's goal block, plus the Scorecard's timing rows,
read from `bp3 q r` (`timing.dwell_s.handed_off`).

## Goal and why

Make the per-node loop minutes long without losing the reviewer. The
slow part was never the gates (`make check` 9s, `make check-full`
36s); it was open-ended grades that found self-checkable problems and
widened scope each round. Owner: "I still want clear, dead simple,
correct code. but at smaller increments, quicker feedback loops."

## Success picture

- Every node of this quest hands off with a receipt, and every grade
  ran the three jobs.
- Grades take about five minutes or less (measured), with no grade
  adding a requirement that is not an acceptance row or a proven bug.

## Scope

| In | Out |
|---|---|
| `scripts/red-first`, `scripts/receipt`, their fixture tests and table rows | engine changes (no new edge, field or plan) |
| `skills/induct-inline/SKILL.md` and its renders | the `induct` workflow grader (`skills/induct/workflows/induct-grade.js`) |
| the CLAUDE.md / AGENTS.md "fix edge" line | CONSTRAINTS.md and CONTEXT.md (the constraints-context quest) |
| | mutation tools, coverage tools, grader model choice in the engine |

## Human touchpoints

- Approve this file (the only gate before build).
- Promote at the end (`goal_fin`).

## Grade brief for this quest

From verify.1 on, this quest is graded with the narrow brief that
grade.1 writes into the skill, so the timing is measured from the
first node. Until verify.2 lands there is no receipt script: job 1
runs `make check-full` and `./scripts/red-first <sha>` directly, and
the handoff reason carries their exit codes and summary lines.

> Grade commit `<sha>` of node `<node>` in quest `<quest>`. You did
> not write it. Work in the quest desk, which is clean at `<sha>`;
> leave it clean at `<sha>` unless you commit a fix. Three jobs, about
> five minutes: (1) run `./scripts/receipt` and compare it with the
> handoff receipt below; (2) name the one bug the tests most likely
> miss in this diff and probe it (for a test-only commit, break one
> line of the code the new tests cover and confirm red); (3) list
> every claim in the commit message not backed by the receipt, the
> diff or your probe. Return `needs_fix` only for a failing acceptance
> row below or a bug your probe proved; then commit the fix with a
> test, run `./scripts/receipt`, and return the fix sha and receipt.
> Everything else is a follow-up and the verdict is `ship`. If a job
> could not run, return `incomplete` and why. No `bp3 q` calls.

## Nodes

### Milestone: verify

| Node | TL;DR |
|---|---|
| [verify.1 - red-first](nodes/node-verify-1-red-first/NODE.md) | a commit's changed tests must fail on its parent's code; `refactor:` must stay green |
| [verify.2 - receipt](nodes/node-verify-2-receipt/NODE.md) | three printed lines of evidence are the handoff reason |

### Milestone: grade

| Node | TL;DR |
|---|---|
| [grade.1 - narrow-brief](nodes/node-grade-1-narrow-brief/NODE.md) | induct-inline: three-job grade, scoped `needs_fix`, role swap; drop the phantom fix edge |

## Scorecard

| Row | Target | Read from |
|---|---|---|
| grade wall time | median ≤ 5 min over this quest's grades | `bp3 q r`, `timing.dwell_s.handed_off` per cycle |
| re-grades | ≤ 1 per node | `bp3 q r`, `cycle` |
| scope | 0 `needs_fix` outside the two grounds | grade reasons in the ledger, read with `bp3 q <quest> n <node> r` |
| red-first cost | < 30s on this repo | verify.1 goal block |

## Risks and red chair

Not yet written; the quest went on hold before its red chair. Input
for the thaw, from the 2026-11-19 fact-check (recorded in CONTEXT.md
by the constraints-context quest):

- The role swap (grader writes the fix, author grades it) has no prior
  art found; the common pattern is a read-only reviewer. Mixed ground.
- Missing practice: lock red tests. Agents delete or edit failing
  tests to go green; the receipt proves commands ran, not that tests
  stayed honest. A thaw should add changed-test counts to the receipt
  and make an unjustified weakened test a `needs_fix` ground.
- Published QA rounds ran 6.8-9.6 min; a 5-min median is ambitious.

## Open questions

1. Align or retire the `induct` workflow grader
   (`skills/induct/workflows/induct-grade.js`, 1022 lines) once the
   narrow grade has numbers. Owner.
2. Run the grader on a cheaper model (Sonnet) by default? Measure on
   this quest first. Owner.
## Node diagram

```text
verify.1 red-first ──► verify.2 receipt ──► grade.1 narrow-brief
```
