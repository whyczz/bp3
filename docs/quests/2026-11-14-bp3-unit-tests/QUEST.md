---
status: canceled
home_repo: bp3
date: 2026-11-14
---

# bp3-unit-tests: the test split, standard and backfill

> **Canceled (2026-11-25):** Abandoned by owner on 2026-11-15 (`bp3 q` rollup state `deleted`) and superseded by [2026-11-18-test-pyramid](../2026-11-18-test-pyramid/QUEST.md) (merged `73130841`).

TL;DR
bp3 gains the missing bottom layer of its test pyramid —
QCheck/OUnit tests for the pure hermetic_fns of `bp3 q` — and the
framing standard that keeps it from going missing again:
every future exp declares its test split (unit / fixtures /
demos) up front. Promoted from
[the OCaml unit tests icebox entry](ICEBOX.md) (retired
2026-11-15 at the owner's call: fossil copied verbatim
into this quest folder, entry deleted, git history
keeps the other copy);
promotion per the `quest` skill: transcription, not
adoption — everything below was re-decided in framing.

ELI5
Today the only tests drive the whole program from outside,
like crash-testing a car to check its spark plugs. This
quest tests the spark plugs directly, and makes "which
tests does this exp need?" a question every future exp
answers before it starts, not after it breaks.

## Terms

| Term | One line |
|---|---|
| Test split | an exp's declared three levels: unit, fixtures, demos |
| Unit test | a hermetic test: a fast, deterministic check of one hermetic_fn, run by `dune test` (QCheck/OUnit — what's installed; no Alcotest pin). *Hermetic* is the concept (red-ink round 7, owner, 2026-11-15): sealed from clock, env, git, filesystem; inputs passed in or replayed, never fetched |
| Tape | sanitized prod/debug data, frozen as a checked-in test input and replayed into a hermetic_fn — real nastiness, deterministic replay. Deliberately *not* a Run's `tape.log`: that is verbatim evidence, never parsed into facts; a Tape here is data deliberately extracted, sanitized, and adopted as a test input |
| Law | a property that must hold for all inputs (round-trip, invariance), tested by generation, not examples |
| Characterization | a unit test that pins today's behavior, labeled as such; it describes, it does not bless |
| Fixture | today's shell level (`test/*.sh`): end-to-end, gates `make check`, unchanged by this quest |
| hermetic_fn | a function a unit test can call with no git, process, wall clock, env, or filesystem — every input passed in: `fold_ledger`, `ledger_line`, `parse_edge_cycle`, kind mapping, stale gate (once `~now` is injected) |
| Lint rule | one machine-checkable sin, as data: id, severity, pack (ocaml \| cli), checker (command \| pattern), message. Owned by the future `bp3 lint` quest — split out at red-ink round 1 and frozen as [bp3-lint](../../icebox/2026-11-15-bp3-lint.md); never prose in a skill |

## Demos

### Design trace — the hermetic_fn under test (nothing here has run yet)

```text
ledger text with an event line in the middle
  -> fold_ledger
  -> same state as the ledger without it      (law: event lines never move state)
ledger_line(...) -> decode -> same fields      (law: round-trip)
binding last seen 899s ago -> survives sweep
binding last seen 901s ago -> run_unsettled    (stale-gate boundary)
```

### Observed — the gap this quest fills

```text
$ find . -name 'test_*.ml' -not -path './_build/*'   ->  (nothing)
$ opam list | grep -i alcotest                        ->  (nothing)
$ opam list | grep qcheck                             ->  qcheck 0.91 (+ core, ounit)
$ time make check                                     ->  real 0m24.664s, all shell level
```

## Goal and why

The MVP quest landed 1,389 lines of OCaml whose pure core
has no targeted tests. The one real defect it produced (the
sweep age gate) was caught by review judgment, not by a
test — luck, formalized after the fact as fixtures. Fixtures
remain the acceptance gate; they are too coarse to guard a
fold. This quest adds the fine layer and writes the
expectation into the framing standard so the next quest
starts with it.

## Success picture

`dune test` runs in `make check`: the two laws green,
boundary cases named, characterization labeled. And an exp
framed after this lands shows a `Tests` line in its record —
unit cases named, or a one-line justified "none."

## Scope

| In | Out |
|---|---|
| `/quest` test-split standard (bp3 skill + exp shape) | retrofitting old exp records |
| QCheck/OUnit suite for the named hermetic_fns (Exp 2 list is exhaustive) | new frameworks (no Alcotest), coverage tooling, CI changes |
| `dune test` wired into `make check` | speeding up the shell fixtures (24.6s is accepted) |
| sync of the yap-side exp shape (`red-ink`, `auto-red-ink`) — owner wants it (2026-11-15): hermetic concept, kind-prefixed explicit names, Tape replay land in their `Tests` parts too. Implementation lives in `bp3-yap-skills` under `add-yap-skill` gates; `auto-red-ink` runs "the same walk," so it inherits via `red-ink` unless its own text needs a named edit | yap skill edits without going through that repo's gates |
| — | `bp3 lint` engine + rule packs — split out at red-ink round 1 (owner: B, 2026-11-15), frozen as [bp3-lint icebox entry](../../icebox/2026-11-15-bp3-lint.md); other languages' packs, prose style guides, auto-fix |

## Human touchpoints

Quest approval (this file); Exp 1's exact wording in the
`quest` skill (owner reads skill diffs). The origin
icebox entry is already retired (see TL;DR link);
no promotion marking remains to do.

## Exps

### Exp 1 — [Test-split standard](experiments/exp-1-test-split-standard/NODE.md)
`/quest` gains step-level language: every exp states unit /
fixtures / demos at framing; exps may declare no unit tests
only as a justified one-liner. The exp record tables gain a
`Tests` line. Depends on: none. Lane: standard.

Hermetic standard (red-ink round 7, owner: A, 2026-11-15):
the concept the standard exports is *hermetic* — a unit
test is a deterministic check of a `hermetic_fn`, sealed
from clock, env, git, and filesystem. Inputs are passed
in (a fake clock is an argument), generated, or replayed
from a frozen Tape; never fetched live. A function that
cannot be made hermetic is declared at fixture level in
the `Tests` line, with the reason. This binds every
future exp, not only this quest's Exp 2.

### Exp 2 — [Unit backfill](experiments/exp-2-unit-backfill/NODE.md)
QCheck/OUnit suite under `src/quest/test/` for the named
hermetic_fns and two laws, wired into `make check`. Two lanes:
known cases for speed, property-based for breadth.
Depends on:
Exp 1 (so its own record demonstrates the standard).
Lane: standard.

Spike gate (red-ink round 2, owner: A, 2026-11-15): the
exp opens with a throwaway `dune test` that merely *calls*
each named hermetic_fn. The framing asserts the hermetic_fns are pure
(the origin icebox feared they are not); the spike is the
test of that assertion. Any hermetic_fn needing git/process
extraction parks the exp back to the owner before the
suite is written — extraction is not absorbed silently,
and the hermetic_fn list does not shrink without a call.

Generator shapes (red-ink round 3, owner: C, 2026-11-15 —
explicit, two layers, never conflated):
- **Structured layer** owns the round-trip law: generated
  field tuples over `ledger_line`'s exact shape —
  `edge`, `from`, `to`, `cycle` (int), `commit`,
  `verdict`, `reason`, `id` — including absent/empty
  `commit` and unknown `edge` spellings as values.
- **Raw-text layer** owns the fold laws: mutated ledger
  *text* — malformed JSON lines, wrong-typed fields
  (string where `cycle` expects int), unknown `edge`
  values, event lines spliced at head, middle, and tail,
  `cycle` jumps. This layer pins the fold's actual
  contract as **labeled characterization** (verified
  against `store.ml` during the round, correcting the
  round's first read): wrong-typed fields default
  silently (`get_str`/`get_int`), but malformed JSON
  raises `E_INVALID_PLAN` — it is an error path, not
  leniency — and an unknown `edge` with a `to` field
  still moves `st` and `cycle`. Characterization
  describes today's behavior; it does not bless it.
The acceptance judge grades each layer against its own
shape; a generator that only produces well-formed lines
is timid in both.
- **Tape replay** feeds both layers their reality check
  (red-ink round 7, owner, 2026-11-15): sanitized
  prod/debug data — real ledger text, real hook
  payloads — frozen as checked-in inputs under the test
  tree and replayed into the hermetic_fn. Generators
  explore the space a human can imagine; Tapes preserve
  the nastiness nobody imagined. Sanitized before
  check-in, adopted deliberately as test data — never
  live prod access at test time, and never a Run's
  `tape.log` parsed into facts.

Lifecycle case (red-ink round 4, owner: A, 2026-11-15):
one known case, not a law — a synthetic ledger walking
create → submit → review(ship) → check(pass) → blocked →
resume, folding *every prefix* and asserting `st` plus
the `review_ok`/`check_ok`/`bound` fields at each step.
This pins the fold's choreography (`submit` resets the
flags, `resume` clears `bound`, blocked captures its
fields) at unit granularity; fixtures keep CLI behavior.

Pure tests (red-ink round 5, owner: A, 2026-11-15 —
owner's rule: "pure functions, pure tests," deterministic
or it is not a unit test): the unit layer takes no wall
clock, no environment, no git, no filesystem. Any hermetic_fn
that needs one gets it injected. Named case: the stale
gate (`Unix.time() -. last_seen > stale_after_s`,
`hooks.ml`) is extracted to a pure predicate taking
`~now` — the fake clock is an argument the test supplies,
never the machine's time. This is the one extraction
pre-authorized in advance; the Round 2 spike still parks
on any other. A hermetic_fn that cannot be made pure this way
drops to the fixture layer and says so in the `Tests`
line — it does not get a relative-to-now test that can
go red under load with correct code.

Test names (red-ink round 6, owner: A, amended
2026-11-15 — "very very explicit"): the kind is the
first token of every test name, all files — `law_…`
(property), `case_…` (named example/boundary), `char_…`
(characterization) — and the rest of the name is a full,
plain statement of hermetic_fn, condition, and expected
outcome. No abbreviations, no numbers, no `test_fold_3`.
Examples of the bar:
`law_ledger_line_decodes_back_to_the_same_fields_it_encoded`,
`case_stale_gate_keeps_a_binding_seen_899_seconds_ago_and_sweeps_one_seen_901_seconds_ago`,
`char_fold_moves_state_on_an_unknown_edge_that_carries_a_to_field`.
Red `dune test` output reads as sentences: invariant
broke, boundary moved, or behavior drifted — the last
being a question for a human, not a verdict.

### Exp 3 — split out (red-ink round 1, owner: B, 2026-11-15)

`bp3 lint` no longer rides this quest. Frozen as
[bp3-lint](../../icebox/2026-11-15-bp3-lint.md); thaws as
its own quest when a concrete rule is demanded. The
original exp record stays untouched at
`experiments/exp-3-linters/NODE.md` as the sketch
that entry points to. The `Lint rule` term above is
retained only as vocabulary for that future quest.

## Scorecard

| Field | Value |
|---|---|
| Wall time | unmeasured until Runs record it |
| Context tokens | unmeasured per-Run until hooks tally them (they now can: quest-level `usage_recorded` exists on landed quests) |
| Human-active minutes | approval + skill-wording read; rest autonomous |

## Risks and red chair

Red-chair pass at framing (2026-11-14), strongest attacks
and what they changed:

| Attack | Change it made |
|---|---|
| The one real defect was caught by review, not a missing test level — backfill value is speculative | quest split: standard is Exp 1 (the durable value), backfill scoped and second |
| Sketched QCheck laws are near-tautologies of the fold | only two laws survive (round-trip; event lines never move state); the rest are examples/characterization, labeled |
| Alcotest isn't installed; QCheck is | framework fixed to QCheck/OUnit; no new dep pin |
| Speed argument is weak (make check 24.6s) | motivation restated: regression precision and failure legibility for LLM children, not seconds |
| Tests ossify a young hermetic_fn | hermetic_fn list is exhaustive and small (1,389 LOC core); characterization is labeled, so future refactors know what they're breaking |

## References — why this quest does not mandate TDD

Settled at the landing red chair (2026-11-14): this quest
asks for tests up front as *declared split*, not as a
red-green-refactor loop inside Runs. The evidence:

| Source | What it found |
|---|---|
| [Thoughtworks experiment, Böckeler (summary)](https://www.sigist.se/community/error-500-internal-testing-times-does-tdd-actually-help-inside-an-ai-agents-loop) | no better designs, tests, or mutation scores from TDD prompting an agent; 3–8× token cost |
| [Dan Luu, agentic test/verification evaluation](https://theagenttimes.com/articles/ai-agents-struggle-with-testing-techniques-even-when-explici-30828822) (~4,800 runs, 26–30 instruction conditions, Zstd in Rust; pre-registered 55% that TDD underperforms) | TDD did not clearly outperform the default condition; technique instructions mostly didn't move outcomes. Primary notes: [danluu.com](https://danluu.com/ai-coding/) |
| [HN: nudging agents into red/green/refactor](https://news.ycombinator.com/item?id=49953270) | practitioners unconvinced; TDD's human value (forced small-step thinking) doesn't transfer mechanically; assurance that tests exist is the part that survives |
| Counterweight, recorded honestly: [Fowler digest](https://ai-tools-aggregator-seven.vercel.app/blog/2026-02-19-martin-fowler-ai-debt-accelerator), [tests-as-spec](https://www.caimito.net/en/blog/2026/04/17/tests-beat-instructions-for-ai-coding-agents.html) | strong teams report TDD essential with LLMs — consistently with human-owned, author-immutable test suites. That separation is what this quest standardizes (owner/standard-owned tests, separate judge children), without the ritual loop |
| Hazard that shapes the guardrails: [EvilGenie reward-hacking benchmark](https://ranmaul.com/en/notes/dont-let-agent-grade-own-homework) | agents hardcode, rewrite, and delete tests they own; hence author-immutability everywhere in this quest |

## Open questions

| # | Question | Owner |
|---|---|---|
| 1 | ~~Does the test-split standard also land in the yap `red-ink`/`auto-red-ink` exp shapes, or bp3-only for now?~~ Settled 2026-11-15: yes, both — hermetic concept, explicit kind-prefixed names, Tape replay (see Scope). Implementation owed in `bp3-yap-skills` via `add-yap-skill` | human (settled) |
| 2 | ~~Is `promoted:` set on the icebox entry at this Quest's approval?~~ Settled 2026-11-15, stronger: entry retired — fossil at `ICEBOX.md` in this folder with `promoted:` set, entry deleted | human (settled) |
