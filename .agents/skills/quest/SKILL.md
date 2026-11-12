---
name: quest
description: Turn a known intent into a bp3 Quest file at docs/quests/<date>-<slug>.md with exps, acceptance checks, and human touchpoints.
---
<!-- GENERATED from skills/quest/SKILL.md by: bp3 skills install --harness=muse. Edit the source, then re-run. -->

# Quest

```text
known intent
    |
    v
 sync -> research -> names -> exps -> red chair
    |                                   |
    +-------> docs/quests/<date>-<slug>.md
                        |
                 human approves
                        |
                   governs build
```

```python
def quest(intent):
    assert known(intent)                 # fuzzy goal -> ask()
    play_back(intent)                    # iiuc, when two reads exist
    ground = research(mvp_doc, repo, prior_quests)
    names = define_terms(intent)         # spellings synced with code/data
    exps = break_down(intent, acceptance="fails today")
    attack(goal, scope, exp_order)       # red chair, recorded
    return write_quest_file(names, exps)  # governs after human approval
```

One output: a Quest file a build can run against.

## Context

Reading map for this skill: prose carries context, why, and how
we got here. Diagrams, pseudocode, and tables carry what we do.

Work here used to live in the coordinator's head: helpers started
blank, re-learned the job, and the plan evaporated between
sessions. A Quest file moves that intent into the repo, where
every later session reads the same map.

How we get there shapes the procedure below. Sync comes first
because a dictated intent usually has two honest reads, and
speccing the wrong one costs a whole Quest. Research comes
before questions because the repo already holds most answers.
Names come before exps because names harden into paths, CLI
addresses, and ledger fields. Acceptance must fail today
because a gate that starts green certifies nothing.

## When this fires

| Case | Fire |
|---|---|
| “frame this as a quest”, `/quest` | this skill |
| goal or success test still fuzzy | `ask` first |
| component design, no Quest shape | `design` |
| idea shelved for a future quest | `icebox` |
| advancing existing quest state | `using-bp3` |

## Procedure

| # | Step | Gate before moving on |
|---|---|---|
| 1 | Sync: play the intent back (iiuc) when it can be read two ways | human confirms the read |
| 2 | Research the ground: MVP doc, home repo state, prior Quests in `docs/quests/` | every claim traces to a file read this session |
| 3 | Ask questions whose answers change the shape: home repo, success picture, lane, first exp | the rest become assumptions or open questions in the file |
| 4 | Names first, under a Concepts/Terms header, with `naming` | every term defined in one line before any exp spends it |
| 5 | Draft `docs/quests/<date>-<slug>.md` (`YYYY-MM-DD`, short kebab slug) | one Quest per file |
| 6 | Break into exps with failing-today acceptance | a check that cannot fail gets rewritten |
| 7 | Red-chair passes on goal, scope, exp order | strongest attack + what it changed, recorded |
| 8 | Stage fat exps as numbered substeps (1.1, 1.2, ...) | each substep passes on its own |

Keep exp detail inside the Quest file: intent, order, dependencies,
acceptance. Deep runbooks live in linked exp records; the Quest
file stays the plan of record.

## Names sync with code and data

Names become folder paths, CLI addresses, ledger fields, and the
words later sessions think in.

| Term becomes | Spelling rule |
|---|---|
| CLI verb / flag | exact identifier from the CLI |
| state / variant | exact spelling from the FSM or type |
| ledger field | exact key the binary writes |
| file / branch | exact path or ref the tools derive |
| coined fresh | the Quest's spelling; implementation adopts it |

| Case | Move |
|---|---|
| code or data already has a name | Quest adopts that spelling |
| Quest coins a name | code, schemas, tests, skills take the Quest spelling |
| rename after exps reference it | treat it as a migration; price it before agreeing |

## Exps

The Quest file keeps the railway: one TL;DR row per exp, with a
relative link to its record. Full Output, Acceptance, and
Substeps live in `experiments/exp-<n>-<slug>/EXPERIMENT.md`
inside the quest folder — the same folder that later holds the
exp's generated ledger, state, and runs.

Every exp record is written in this shape, in this order:

```text
TL;DR -> demo -> diagram (ascii) -> pseudocode (python)
      -> tables -> acceptance test (goal block) -> prose
prose = context, why, how we got here, edge cases
code  = what we're gonna do
```

| Part | Carries |
|---|---|
| Demo | up front: one worked trace (happy path at minimum), labeled `observed` or `design trace` |
| ASCII diagram | the flow at a glance: inputs, outputs, where it can stop |
| Python pseudocode | the mechanism, readable by human and agent in one pass |
| Tables | fields (Intent, Lane, Output, Acceptance, Depends on), cases, gates |
| Acceptance test | one goal-shaped block a session can run cold: `objective` (one sentence), `prove by` (fixtures/commands), `done when` (the exact observation) |
| Prose | context, why this exp exists, how we got here, edge cases and what they do |

An exp with no demo and no runnable goal block is unfinished
spec, however good its prose reads. The Quest file itself
follows the same law at its scale: Terms, then a Demos section
(the quest's own traces, honestly labeled), then the railway.

| Field | Carries |
|---|---|
| Intent | the bounded contribution |
| Lane | micro \| standard \| high-blast-radius |
| Output | an artifact someone can inspect |
| Acceptance | a check that fails today, with its expected observation |
| Depends on | prior exps, exact commits, or none |

## File shape

```markdown
---
status: proposed | active | landed | canceled
home_repo: <repo>
date: <YYYY-MM-DD>
---

# <Quest name>

TL;DR
<what will be true when this Quest lands; the one decision made>

ELI5
<the whole Quest in plain words>

## Terms
<every name and term, one line each; spellings match the code
and data structures they name, exactly>

## Demos
<the quest's own worked traces, up front, each labeled
observed or design trace>

## Goal and why
## Success picture
## Scope            (In: / Out: as a table)
## Human touchpoints
## Exps
### Exp 1 — <name>   (one TL;DR row + relative link; the record
carries diagram, pseudocode, tables, and prose per the Exps
section above)
## Scorecard
## Risks and red chair
## Open questions    (ranked, each with an owner)
```

## Lifecycle

| Status | Meaning | Landing evidence |
|---|---|---|
| `proposed` | framed, unstarted | the file itself |
| `active` | building | exps moving under `using-bp3` |
| `landed` | success picture met | human promotion recorded with exact commit + limitations |
| `canceled` | stopped, terminal | disposition: why, each exp's fate, frozen evidence |

Transitions: `proposed -> active -> landed`; `proposed | active -> canceled`.
Files stay in `docs/quests/` for life — exp records point at them.

At `landed`, run `quest-landing-demo` and record its Landing IIUC
(decision record, demo traces, verification, open items) under
Success picture.

| Boundary | Rule |
|---|---|
| Quest status vs exp status | exps keep `proposed \| active \| complete`; `auto_landed` stays exp-level |
| file sync | update at Quest gates; runtime truth lives in bp3 once implementation exists |

## Traps

| Case | Move |
|---|---|
| acceptance reads like a hope | rewrite until it can fail today |
| file claims a result never observed | mark it proposed / unmet |
| new planning vocabulary creeps in | Quest, exp, Run carry the load; send the rest back |
| accepted Quest needs a goal change mid-build | explicit edit, human-approved |
