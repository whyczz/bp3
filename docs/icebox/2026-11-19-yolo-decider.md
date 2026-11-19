---
status: frozen
date: 2026-11-19
promoted: null
---

# Yolo decider and needs_fix_yolo: fewer pages for low-blast-radius fixes

## Context

Frozen 2026-11-19, mid-run of the test-pyramid quest
(`docs/quests/2026-11-18-test-pyramid/`). Owner, verbatim: "yo please
for /induct-yolo we add a YOLO decider?" The owner then chose to
icebox it now and frame it as a quest after test-pyramid.

What happened during that run:

- `bp3 q <quest> n <node> e resume` refuses with `E_HUMAN_REQUIRED`
  unless `BP3_DECIDER=human` (`src/quest/store.ml:63` sets
  `decider_human`; `src/quest/main.ml:152,252` refuse). The induct
  skills forbid the agent to set it ("never attest").
- So in a yolo run, every grader `needs_fix` at the cycle cap sent
  the owner a one-liner to type. The owner cast five resumes over
  three commands (tier.1 three times, unit.2 and unit.3 once); one
  multi-line paste broke on zsh (`parse error near ';'`), and in
  another only the first `!` line ran.
- The default plan already went to `max_cycles: 3` (commit edb32a5 on
  `quest/2026-11-18-test-pyramid`). That cut the pages but did not
  remove them: tier.1 and unit.3 each used all three rounds.

Added the same day, owner verbatim: "i want a needs_fix_yolo, lkike
the blast radius is not big enough for a human to give meaningful
feedback". Evidence from the run: nine `needs_fix` grades so far.
Every one was a test-strength gap (vacuous laws, coverage headers
that overclaimed, weak fixtures) or a flaw in the test runner script.
None was engine behavior. At the cap, each paged the owner, who
typed a resume without changing anything.

Prior art already in the engine: `grade --verdict needs_fix
--mechanical` records `fix_class: "mechanical"` and never blocks
("the cycle cap counts disagreement cycles only",
`src/quest/main.ml:329-335`). The `induct-grade` workflow classifies
each fix as owner, disagreement, mechanical or standard
(`skills/induct/workflows/induct-grade.js` classifyFix). Only
"exact file/line/text, no judgment call" counts as mechanical. In the
test-pyramid run, `induct-inline` asked its graders for no fix class
and cast plain `needs_fix` every time, so even the existing
non-paging lane went unused.

Relation to `2026-11-18-yolo-mode.md`: that entry is the larger
direction (frontier fan-out, an "agent decider", budget as the only
brake). This entry is its smallest slice: the decider plus one
verdict class, with no fan-out or budgets, and can thaw first.

## Sketch

One engine change and one skill change, as separate nodes.

```text
blocked node ──resume──► BP3_DECIDER=human  -> as today
                    └──► BP3_DECIDER=yolo   -> allowed iff the quest opted in
                                               and the node has yolo resumes left;
                                               ledger line says decider: "yolo"
                                               otherwise E_HUMAN_REQUIRED (unchanged)
```

- **Honest identity:** the ledger line records `decider: "yolo"` (or
  `agent`, see blockers) plus the reason. It never claims human.
- **Opt-in per quest:** a plan or config knob such as
  `yolo_resumes: 1`, off by default, so existing quests are unchanged.
- **Scope:** `resume` only. Never `land` without a ship verdict, never
  `delete`, never `goal_fin` or promotion; those stay human.
- **Cap:** N yolo resumes per node (default 1). After that the node
  needs a human again.
- **Report:** `induct-yolo`'s check-in report lists every yolo resume,
  with node, cycle and reason.

### needs_fix_yolo (added 2026-11-19)

A grader verdict for fixes too small for a human to add anything,
between `--mechanical` (one exact edit) and `needs_fix` (judgment).

```text
grader verdict      fix class          at the cycle cap
ship                -                  approved
needs_fix_yolo      yolo (low blast)   todo, another agent round (own cap)
needs_fix           mechanical         todo (today, unchanged)
needs_fix           standard/owner     blocked, pages the owner (today)
```

- **Low blast radius**, by rubric: the fix touches tests, fixtures,
  docs or test scripts only. It changes no engine behavior, CLI
  contract, ledger shape, skill text, or security or data handling.
  The grader names the class and the rubric row it matched.
- **Honest ledger:** cast as `needs_fix` with
  `fix_class: "yolo"` (an existing field), so folds and reports read
  it like `mechanical`.
- **Own cap:** yolo rounds per node (for example 3) are counted apart
  from disagreement cycles. Past that cap, `needs_fix_yolo` becomes
  `needs_fix` and pages the owner.
- **First cheap step** (no engine change): `induct-inline`'s grader
  brief asks for a fix class, and the session casts `--mechanical`
  when it qualifies, the way `induct-grade` already does.

Not added: budgets, fan-out, or any change to who may land or
promote. Those belong to `yolo-mode`.

## Blockers

- **Name:** `yolo` (the owner's word now) or `agent` (the 11-18
  entry's word). Pick one before code; it becomes a ledger value.
- **Where the knob lives:** the plan file (per goal_type), the quest's
  create line, or machine-local config. Retyping a quest after
  creation is not possible today.
- **Cap semantics:** per node, per quest, or both; whether a human
  resume resets the count.
- **Who classifies, and laundering:** the grader picks the class.
  Without a rubric, a grader (or a lenient brief) could file a real
  defect as `yolo` and it would never reach a human. Needs a written
  rubric, a rule that any behavior or contract change is never yolo,
  and the human audit in `induct-yolo`'s check-in report.
- **Overlap:** `needs_fix_yolo` may make the decider unnecessary for
  most of these pages: a fix that never blocks needs no resume. Decide
  whether both ship, or `needs_fix_yolo` (plus the inline grader's
  fix class) first.
- **Mechanical vs yolo:** widen `fix_class: mechanical` (and the
  classifyFix regexes), or add a separate `yolo` class.
- **Fixtures:** the `blocked.sh`/`g.sh` assertions that pin
  E_HUMAN_REQUIRED must keep passing; new fixtures need opt-in absent,
  present, and cap exhausted.

## Promotion trigger

The test-pyramid quest lands (the owner chose: icebox now, quest
after).
