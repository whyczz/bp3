---
name: quest
description: Turn a known intent into a bp3 Quest file at docs/quests/<date>-<slug>.md with nodes, acceptance checks, and human touchpoints.
---
<!-- GENERATED from skills/quest/SKILL.md by: bp3 skills install --harness=claude. Edit the source, then re-run. -->

# Quest

```text
known intent
    |
    v
 sync -> research -> names -> nodes -> red chair
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
    nodes = break_down(intent, acceptance="fails today")
    attack(goal, scope, node_order)       # red chair, recorded
    attack(source)                       # the icebox/prompt itself
    for c in concerns if c.severity in (critical, major):
        settle(c) or append_followup_node(c)   # proof owed, not prose
    return write_quest_file(names, nodes)  # governs after human approval
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
Names come before nodes because names harden into paths, CLI
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
| 0 | Clean-runway guard: if already in a non-master worktree (`quest/*` or `draft/*`), proceed directly; if on `master`/`main`, run `bp3 harness desk prepare --draft quest-<slug>` before writing any file — never leave uncommitted multi-turn quest drafts on `master` | draft desk active (or non-master worktree); on approval, commit cleanly and run `bp3 harness desk land --draft quest-<slug>` |
| 1 | Sync: play the intent back (iiuc) when it can be read two ways | human confirms the read |
| 2 | Research the ground: MVP doc, home repo state, prior Quests in `docs/quests/`, and the root `CONSTRAINTS.md` (the owner-signed stack) and `CONTEXT.md` (how others build this, sourced and dated) | every claim traces to a file read this session |
| 3 | Ask questions whose answers change the shape: home repo, success picture, lane, first node | the rest become assumptions or open questions in the file |
| 4 | Names first, under a Concepts/Terms header, with `naming` | every term defined in one line before any node spends it |
| 5 | Draft `docs/quests/<date>-<slug>.md` (`YYYY-MM-DD`, short kebab slug) with `bump: major \| minor \| patch \| none` per `RELEASING.md` (`scripts/check-bump` enforces it in `make lint`) | one Quest per file |
| 6 | Break into nodes with failing-today acceptance | a check that cannot fail gets rewritten |
| 6.5 | Diligence gate per node: design settled (no open questions), acceptance fails today, acceptance gates defined up front | an node with open design questions is not ready for `induct`; settle it with `red-ink` first — Node 4 of the MVP quest shipped unsettled design and the landing review caught it late |
| 6.6 | Skill changes ride as their own node | if the Quest's changes touch any skill (bp3 `skills/`, yap skills, installed copies), name a skill-change node with its own acceptance (skill tests, render/install assertions); never edit a skill inline during framing, and never fold a skill change into a code node — skills are how children behave, so they get the same gate as code |
| 6.7 | Human touchpoints are irreducible: each names the one thing only a human can give — an approval (AV, a sign-off), a secret, money, a judgment call | everything a machine can do or observe — running commands, attaching and closing terminals, reading logs, answering what the record already proves — is in the node's scripts, so a live run is one command the human starts and the approval they give; a gate that asks the human to type, click or confirm what a script could check gets rewritten (owner, 2026-11-23: "idk why you're expecting the human to do low value things") |
| 7 | Red-chair passes on goal, scope, node order, plus two fixed passes. The **constraints pass**: does the plan add a language, library or surface outside `CONSTRAINTS.md`? Each addition needs a `/teach` pitch and the owner's words before approval. The **common-sense pass**: how would another team build this (`CONTEXT.md`), and why do we differ? Re-run a claim's saved search first when it is older than 90 days | strongest attack + what it changed, recorded; both passes recorded, "none" allowed |
| 7.5 | Red-chair the source itself: the icebox entry or the owner's prompt (its assumptions, wrong problem, boring alternative), before approving the draft built on it | every **critical or major** concern ends in exactly one of two places: settled by a recorded change to the design it attacked, or appended as a **follow-up node** (next numbers on the railway, labeled `(follow-up)`) whose acceptance proves the design addressed it. A critical/major concern left as prose in Risks, or with neither settlement nor node, blocks approval |
| 8 | Stage fat nodes as substeps inside their milestone (`mvp.1.1`, `mvp.1.2`, ...) | each substep passes on its own |

Keep node detail inside the Quest file: intent, order, dependencies,
acceptance. Deep runbooks live in linked node records; the Quest
file stays the plan of record.

## Promotion from the icebox

A Quest that starts from a `docs/icebox/` entry promotes it.
Promotion means exactly this, no more. The `ICEBOX.md` copy
rule applies whenever a Quest is written from an entry, not
only at formal promotion:

| Step | Rule |
|---|---|
| Trigger check | the entry's stated promotion trigger has observably fired; the owner names the entry |
| Transcription, not adoption | the entry is research input to step 2, nothing more. This skill's whole procedure still runs: sync, research, names, nodes, red chair. Every assumption the entry made is re-decided here; entry text is never copied in as settled design |
| Link both ways | the Quest file names the entry in its Context; the entry gains one field (below) |
| Context copy & delete | whenever a Quest is framed from an entry, copy the entry **verbatim** to `ICEBOX.md` in the Quest folder (a straight-up copy, never transcribed into prose) and **delete the original entry from `docs/icebox/` right away** (owner rule, 2026-11-23): the frozen context travels with the Quest, no duplicate stays in `docs/icebox/`, and git history is the fossil of the day the idea was shelved. The Quest file links `ICEBOX.md` wherever it would have linked the entry |
| Marking | record the promoted entry's original path in `QUEST.md` Context (and `promoted:` if updating an existing entry before deletion); the Quest file is now the living record |
| Thaw that dies | if the framed Quest is canceled before landing, restore the entry from git history with `promoted:` still set: it records that the thaw happened and where it went |

An entry without a fired trigger is not promotable; a
Quest framed from one anyway says so in its Open questions.

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
| rename after nodes reference it | treat it as a migration; price it before agreeing |

## Nodes

The Quest file keeps the railway: one TL;DR row per node, with a
relative link to its record.

Node names are grouped by milestone. The display name is
`<milestone>.<number> - <slug>` (for example,
`mvp.1 - supervisor-cli`, `backtest.1 - muse`,
`dogfood.1 - muse-toy-quest`). Because bp3 slugs cannot
contain dots, the folder and bp3 node ID use the dotless
spelling `node-<milestone>-<number>-<slug>`, and the record
frontmatter carries `node: <milestone>.<number>`. Numbering
restarts inside each milestone; never use a bare global
`Node N` for a new quest. Dependencies name display names,
not bare numbers.

Full Output, Acceptance, and Substeps live in
`nodes/node-<milestone>-<number>-<slug>/NODE.md`
inside the quest folder — the same folder that later holds
the node's generated ledger, state, and runs.

Every node record is written in this shape, in this order:

```text
TL;DR -> acceptance gates -> diagram (ascii) -> pseudocode (python)
      -> tables -> prose
prose = context, why, how we got here, edge cases
code  = what we're gonna do
```

| Part | Carries |
|---|---|
| Acceptance gates | up front: one worked trace (happy path at minimum), labeled `observed` or `design trace`, then one goal-shaped block a session can run cold: `objective` (one sentence), `prove by` (fixtures/commands), `done when` (the exact observation) |
| ASCII diagram | the flow at a glance: inputs, outputs, where it can stop |
| Python pseudocode | the mechanism, readable by human and agent in one pass |
| Tables | fields (Intent, Lane, Output, Acceptance, Depends on), cases, gates |
| Prose | context, why this node exists, how we got here, edge cases and what they do |

A node with no acceptance gates (worked trace plus runnable goal block) is unfinished
spec, however good its prose reads. The Quest file itself
follows the same law at its scale: Terms, then Inputs, then
Outputs, then an Acceptance gates section — one worked trace of
the whole quest, honestly labeled, and the checks that prove it —
then the railway. A Quest file with Inputs/Outputs but no
Acceptance gates is unfinished the same way: the reader must see
the machine run before reading its parts. A recorded or
hands-on demo is a different thing: that is `warden`'s job.

| Field | Carries |
|---|---|
| Intent | the bounded contribution |
| Lane | micro \| standard \| high-blast-radius |
| Output | an artifact someone can inspect |
| Acceptance | a check that fails today, with its expected observation |
| Depends on | prior nodes, exact commits, or none |

## File shape

```markdown
---
status: proposed | active | landed | canceled
home_repo: <repo>
date: <YYYY-MM-DD>
bump: major | minor | patch | none
---

# <Quest name>

TL;DR
<what will be true when this Quest lands; the one decision made>

ELI5
<the whole Quest in plain words>

## Terms
<every name and term, one line each; spellings match the code
and data structures they name, exactly>

## Inputs
<what the quest takes in: calls, flags, env, config, files —
one row each, with source and precedence where they compete>

## Outputs
<what the quest emits: verdicts, artifacts, files, error
codes, exits — one row each>

## Acceptance gates
<one worked trace of the whole quest running end to end, right
after Inputs/Outputs, labeled observed or design trace, then the
checks that prove it>

Worked example (miniature — voice and scale, not a template):

```markdown
## Inputs
| Input | Source |
|---|---|
| link token | one-line brief from the conductor |

## Outputs
| Output | Shape |
|---|---|
| edge verdict | `{state, run_id, source}` stamped from the claim |

## Acceptance gates (design trace)
root: mint link -> node claims -> edge claims -> handoff -> landed;
blocked sibling: edge fails typed -> node blocks, exits -> root pages
human -> resume -> fresh node worker continues.
```

## Goal and why
## Success picture
## Scope            (In: / Out: as a table)
## Human touchpoints  (only what needs a human: an approval, a secret, money, a judgment; step 6.7)
## Nodes
### Milestone: <milestone>
### <milestone>.1 - <slug>   (one TL;DR row + relative link;
the record carries diagram, pseudocode, tables, and prose
per the Nodes section above)
## Scorecard
## Risks and red chair
## Open questions    (ranked, each with an owner)
## Node diagram
<closing ASCII diagram: every node as a node, dep arrows,
cohort layers — the railway in one picture, at the end>
```

The Quest file ends with the Node diagram: after reading
every node's prose, the reader gets the whole railway —
nodes, dependencies, cohorts — in one ASCII picture.

Keep the living run record in a companion `LOG.md` beside
`QUEST.md` (same quest folder; never named `LEDGER.md`, which
would collide with generated `ledger.jsonl`): `LOG.md` holds the
node status/cycles table, build notes, measured scorecard, new
findings, follow-ups, and lessons learned while `QUEST.md` stays
the clean plan of record.

## Lifecycle

| Status | Meaning | Landing evidence |
|---|---|---|
| `proposed` | framed, unstarted | the file itself |
| `active` | building | nodes moving under `using-bp3` |
| `landed` | success picture met | human promotion recorded with exact commit + limitations |
| `canceled` | stopped, terminal | disposition: why, each node's fate, frozen evidence |

Transitions: `proposed -> active -> landed`; `proposed | active -> canceled`.
Files stay in `docs/quests/` for life — node records point at them.

At `landed`, run `warden` to record `FEEDBACK.md` and the Landing IIUC
(decision record, the demo run, verification, open items)
under Success picture.

| Boundary | Rule |
|---|---|
| Quest status vs node status | nodes keep `proposed \| active \| complete`; `auto_landed` stays node-level |
| file sync | update at Quest gates; runtime truth lives in bp3 once implementation exists |

## Traps

| Case | Move |
|---|---|
| acceptance reads like a hope | rewrite until it can fail today |
| red-chair concern parked as a Risks paragraph | Risks is not a parking lot: a critical/major concern is settled in the design or appended as a follow-up node (step 7.5); prose is neither |
| file claims a result never observed | mark it proposed / unmet |
| new planning vocabulary creeps in | Quest, node, Run carry the load; send the rest back |
| accepted Quest needs a goal change mid-build | explicit edit, human-approved |
| a live or e2e check asks the human to type a word, open or close a window, or answer y/N | script it (a pty for a terminal, the log for what happened); the human starts one command and gives only the approval a human must give (step 6.7) |
| framing session "just quickly fixes" a skill | stop; it becomes a skill-change node (step 6.6). The only direct-now path is the owner explicitly invoking `/add-yap-skill` or `/add-bp3-skill` — that invocation *is* the order; without it, no inline skill edits |
