---
status: proposed
home_repo: bp3
date: 2026-11-21
---

# metric-followups: the loose ends metric-collectors left

TL;DR
Close the follow-ups metric-collectors left. The one decision: the
version guard moves from argv shapes to the write chokepoint, because
the documented `n <node> e <edge>` form writes past it today (observed).

ELI5
An old bp3 must never write into a repo a newer bp3 has touched. Today
it checks the shape of the command line, and most commands slip past
that check. After this quest, the check sits at the one place every
write goes through. Three small items ride along: author numbers that
can't be trusted are refused like grade numbers already are, new repos
get ten review rounds like this one, and two skills stop naming rules
that no longer exist.

## Context

The follow-ups were listed when metric-collectors landed (promoted as
22b7c44, 2026-11-21). Owner, 2026-11-21: "let's promote, then let's
start the followups". Each was re-checked against master today:

| Follow-up as listed | Read today | Fate |
|---|---|---|
| `metrics scrape` skips the version guard | wider: `n <node> e`, `e`, `n c`, `dep`, scrape and hooks all skip it (probe below) | guard.1 |
| `s_bad_usage` not surfaced for author windows | true: `author_pass` never reads it | usage.1 |
| init-repo scaffolds `max_cycles: 3` | true: `src/quest/main.ml:684` | init.1 |
| induct-yolo says "`bp3 q u` is the only writer" | true: `skills/induct-yolo/SKILL.md:139`, while induct's step 5 scrapes | skills.1 |
| using-bp3 lists `cancel` | true: no such edge (`Store.legal_edges`); `--mechanical` never named | skills.1 |
| `test/skills.sh` false positive on "grade" in a path | true and wider: the grep's file names (`induct-grade.js`, `induct-land.js`) match too | skills.1 |
| induct-grade.js mentions `fix_first` | not stale: it maps the code-reviewer skill's verdict word to `needs_fix` | dropped |
| `wall_s` counts a resumed grader's idle gap | unproven: needs real resumed-grader data first | out, Open question 1 |
| H5/H6 synthetic cast gaps | never seen in real data | out, Open question 2 |
| muse/pi runs not scraped | its own quest (metric-collectors Open question 2) | out |

## Terms

| Term | Meaning |
|---|---|
| version guard | the refusal `E_VERSION_AHEAD` an older-MAJOR binary gives instead of writing in a repo a newer MAJOR stamped (Node 5) |
| `guard_write` | today's guard: argv patterns checked in `Main.run` before dispatch; deleted by guard.1 |
| write chokepoint | `Gitx.commit_files`, plus land's two direct `update-ref` calls, which become `Gitx.move_ref` |
| `Gitx.write_guard` | a `(unit -> unit) ref` every chokepoint call runs first; `Main` sets it to the major-ahead check |
| bad usage line | an assistant line whose usage lacks one of its four counts (`Claude_tx.usage_of` returns `None`) |
| `author_bad_usage` | tally bucket: author windows holding at least one bad usage line; they write nothing |
| host cap | `max_cycles` in the `plans/default.yaml` that `bp3 init-repo` scaffolds |

## Inputs

| Input | Source |
|---|---|
| any `bp3 q` write, in any form | CLI, hooks |
| newest stamped `bp3_version` | `Store.version_ahead`, read from ledgers |
| Claude Code main-session transcripts | `~/.claude/projects/<slug>*/<session>.jsonl` |
| `bp3 init-repo` in a host repo | CLI |

## Outputs

| Output | Shape |
|---|---|
| refused write | `{"ok":false,"error":{"code":"E_VERSION_AHEAD","facts":{"binary","repo"}}}`, exit 1, no ref moved |
| scrape tally | gains `author_bad_usage`; `buckets_add_up` counts it; any > 0 exits 1 |
| scaffolded plan | `plans/default.yaml` with `max_cycles: 10` |
| skill text | induct-yolo Rules, using-bp3 step 4, test/skills.sh gate grep |

## Acceptance gates (observed today, then design trace)

Observed 2026-11-21, scratch repo, node ledger stamped `99.0.0`,
binary `0.2.0`:

```text
$ q demo u pf block --reason "u form"         -> {"ok":false,"code":"E_VERSION_AHEAD"}
$ q demo n pf e block --reason "n e form"     -> {"ok":true,"state":"blocked"}     # wrote past the guard
$ q demo metrics scrape                        -> {"ok":true}                      # nothing to write here; code read says unguarded
```

Design trace after the quest:

```text
guard.1  every write form in that repo -> E_VERSION_AHEAD, every ref unmoved; reads still answer with W_VERSION_AHEAD
usage.1  fixture window with one usage-less line -> author_bad_usage 1, no author samples, scrape exit 1
init.1   bp3 init-repo in a scratch host -> plans/default.yaml says max_cycles: 10
skills.1 test/skills.sh -> induct-yolo names the scrape write; using-bp3 lists the real edges; a planted
         `make check` line in induct-grade.js that names no gate no longer trips the gate grep
all      make check-full rc 0
```

## Goal and why

Close what metric-collectors left open, smallest first after the one
real bug. The guard gap matters most: the form CLAUDE.md documents
and induct casts with is the one that skips the guard.

## Success picture

Every write refuses the same way in a newer-MAJOR repo, and a test
proves it per form. No number bp3 writes comes from a line it could not
read. A new host repo matches this repo's review cap. The skills
describe the engine that exists.

## Scope

| In | Out |
|---|---|
| guard at the write chokepoint (guard.1) | `wall_s` for resumed graders (Open question 1) |
| author windows refuse bad usage (usage.1) | H5/H6 variable-binding gaps (Open question 2) |
| init-repo scaffolds `max_cycles: 10` (init.1) | muse/pi scraping (its own quest) |
| induct-yolo, using-bp3, test/skills.sh (skills.1) | QUEST.md `status:` fields of landed quests |

## Constraints at approval

Constraints pass: none. OCaml, shell and skill text only, all already
in CONSTRAINTS.md. Common-sense pass: git refuses a newer
`core.repositoryformatversion` or an unknown `extensions.*` once, when
it opens the repository, not per subcommand (from memory of git's
`setup.c`, not re-checked this session). guard.1 likewise checks in one
place, at the write chokepoint.

## Human touchpoints

| When | Owner |
|---|---|
| approval of this frame | owner |
| each grade | one fresh grader subagent per commit, `/induct-inline` with yolo (owner's call at approval) |
| promotion | owner |

Decisions at approval (owner, 2026-11-21, answering the frame's questions):

| Question | Owner's answer |
|---|---|
| approve the 4-node frame | "Approve as-is" |
| who grades | "Fresh grader, yolo": `/induct-inline` with a fresh grader per commit, no pages until promotion; lifts the no-graders rule for this quest |
| cleanup | release the metric-collectors and constraints-context desks; remove the empty `node-ctx-1-agent-ground/` dir (done the same day) |

## Nodes

### Milestone: guard

| Node | TL;DR |
|---|---|
| [guard.1 - write-guard](nodes/node-guard-1-write-guard/NODE.md) | the version guard runs at the write chokepoint, so no write form skips it |

### Milestone: usage

| Node | TL;DR |
|---|---|
| [usage.1 - author-usage](nodes/node-usage-1-author-usage/NODE.md) | an author window holding a usage-less line writes nothing and is counted |

### Milestone: init

| Node | TL;DR |
|---|---|
| [init.1 - host-cap](nodes/node-init-1-host-cap/NODE.md) | `bp3 init-repo` scaffolds `max_cycles: 10` |

### Milestone: skills

| Node | TL;DR |
|---|---|
| [skills.1 - stale-rules](nodes/node-skills-1-stale-rules/NODE.md) | induct-yolo and using-bp3 match the engine; the gate grep reads lines, not file names (skill node) |

## Scorecard

Wall time and author cost per node from `bp3 q <quest> metrics r`
(author windows only; no grader transcripts unless graders run).

## Risks and red chair

Strongest attack: "a hook ref is global mutable state; a caller that
forgets to set it gets no guard." Settled: the ref is set once in
`Main.run` before dispatch, every binary entry goes through `Main.run`,
and guard.1's test drives each form through the real binary. Unit tests
that call `Gitx` directly see the no-op default, which is correct for
them.

Attack on the source (the follow-up list): it was written from memory
at the end of a long session. Settled by re-reading each item on master
(Context table): one was wider than listed, one was wrong (`fix_first`)
and was dropped.

## Open questions

1. Does a resumed grader's idle gap reach `wall_s`, or does the
   cross-check already reject it as `mismatched`? Owner: the next quest
   that resumes a grader; needs one real transcript.
2. Are H5 (a reassigned `Q=`) and H6 (an env-prefix `Q=quest cmd $Q`)
   worth closing before one shows up in real data? Owner: owner.

## Node diagram

```text
guard.1 ──┐
usage.1 ──┼──> (no deps between them; one quest branch, landed in this order)
init.1  ──┤
skills.1 ─┘
```
