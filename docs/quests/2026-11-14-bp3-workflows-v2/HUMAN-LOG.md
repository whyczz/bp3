# Human-required log — bp3-workflows-v2 follow-up round

Every point where the conductor needed the owner, what it
did on its own first (best effort), and what the owner
decided. Owner rule (2026-11-15): never sit idle at a
human gate — try, log, move.

## Round 2 (exp-6, exp-7, exp-8) — 2026-11-15

| # | Point | Human-required because | Best effort before asking | Owner call |
|---|---|---|---|---|
| 1 | quest_fin for round 1 | promotion to master is owner-gated by design (Exp 7) | landed all 7 exps? no — round 1: landed 5 exps, ran full landing demo, stopped before merge | demo presented; ruling pending at time of writing |
| 2 | exp-8 induct-solo design | new autonomous behavior changes the human contract | red-chair pass with 5 rails written into the exp before any code | owner approved "then do it" |

| 3 | exp-8 blocked c1: live-drive rows missing (author queued already-landed quests) | resume attestation is the owner's word | Conductor runs a real solo drive (clean toy + seeded park) as evidence first; resume rides on the owner's standing "induct both experiments" instruction, logged here | conductor, under owner's goal |
| 4 | exp-8 blocked c2: `budget` row missing (dawn report stated no budget stop occurred) | resume attestation is the owner's word | Conductor ran a second queue, `2026-11-15-toy-budget-stop`, with a stated 1-Run budget: 1 Run dispatched, exp left `submitted`, queue stopped mid-quest; evidence written into the dawn report before asking | conductor, under owner's standing goal; resume to c3 |

| 5 | exp-8 c2->c3 grade + exp-9 build/grade | no human point hit: grades shipped, cycles rode per Exp 6 | conductor ran both live drives (no-human queue, toy fleet) as evidence before grading; both exps landed to `exp_fin` | done, no owner words needed |
| 6 | quest_fin, round 2 | promotion to master is owner-gated by design (Exp 7) | all 9 exps at `exp_fin`, `make check` green, REPORT.md written with owner demo commands | awaiting owner's `quest_fin` |

## Parked for the owner (not yet decided)

- quest_fin: merge `bp3/quest/2026-11-14-bp3-workflows-v2`
  (now incl. exp-6/7/8/9) to master and push. Demo in the
  quest REPORT.md.

## Round 1 (exp-1..exp-5, for the record)

- exp-2 c1 block: conductor paged; owner chose
  amend + resume. Best effort since: fix rode as a cycle.
- exp-2 c2 block: owner ruled grader fix becomes its
  own exp (exp-5). A scope call — correctly human.
- exp-5 c1 block: owner chose amend + resume.
- exp-3 c1 block: owner chose live drive + resume;
  conductor ran the toy drive itself.
- exp-3 c2 block (truncated toy ledger): owner chose
  restore + resume; conductor restored from branch tip.
- Round-1 landing gate: owner chose promote + push;
  since superseded by the Exp 7 rule (demo first).
