# Exp 9 parallel quests — author notes (c1)

Name: `fleet`, `footprint`, `merge order`, and
`check-in report` reuse the exp's own words; no coinage.
The old output word `dawn report` is replaced by
`check-in report` in this skill (one concept, one word).

Shape: fleet stays a skill mode of `induct`, not a new
FSM. Footprint preflight, merge order, fleet budget,
and the combined report all state as conductor rules
over the exp FSM; no fleet-level state or edges added.

Work:
- `skills/induct-quest-no-human/SKILL.md`: Fleet section
  (footprint defined from QUEST.md Scope + exp Output,
  overlap = same path or directory prefix, no declared
  footprint fails preflight, disjoint quests run in
  parallel, fleet never merges) plus procedure changes:
  merge order declared before the queue starts, first
  in merge order claims its footprint, overlapping quest
  refused at preflight named with zero Runs spent,
  shared work queues serially in a later fleet, one
  fleet budget caps the whole fleet and stops every
  quest, and one combined check-in report (quest_fin
  list in predeclared merge order, parked items grouped
  by quest with inbox reasons, shared-decision parks as
  one decision with dependents, attestation still per
  exp at resume time).
- Installed copies: `.pi`, `.agents`, `.claude` renders
  via `bp3 skills install --harness=all`.
- `test/skills.sh`: 17 fleet assertions (94 total).
- `fleet-drive/CHECKIN-REPORT.md` in this run folder:
  toy fleet preflight drive quoted.

Verification (observed):
- `make check`: exit 0 — shellcheck, check-skills 36
  files, skills tests ok (94 assertions), q, worktree,
  tape, hooks, induct tests ok.
- Toy fleet preflight (`/tmp/fleet-drive/preflight.py`):
  toy-a and toy-b admitted disjoint, toy-c refused
  overlaps toy-a with zero Runs; see CHECKIN-REPORT.md.

Not run / not claimed:
- No live parallel drive of two disjoint toy quests to
  `exp_fin`, no fleet-budget stop, no shared-decision
  park observed. Those need a conductor-run fleet with
  unlanded toy quests; rules are prose + grep tests.

Lessons:
- Grep-asserted phrases must sit on one line; the budget
  sentence was re-wrapped to keep `the budget stopped it`
  on one line for the exp-8 assertion.
- The worktree arrived with exp-8 ledger/state deletions
  already present; they are not part of this commit.
