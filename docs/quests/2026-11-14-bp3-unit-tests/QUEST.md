---
status: proposed
home_repo: bp3
date: 2026-11-14
---

# bp3-unit-tests: the test split, standard and backfill

TL;DR
bp3 gains the missing bottom layer of its test pyramid —
QCheck/OUnit tests for the pure seams of `bp3 q` — and the
framing standard that keeps it from going missing again:
every future exp declares its test split (unit / fixtures /
demos) up front. Promoted from
[the OCaml unit tests icebox entry](../../icebox/2026-11-14-bp3-ocaml-unit-tests.md);
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
| Unit test | a fast check of one pure seam, run by `dune test` (QCheck/OUnit — what's installed; no Alcotest pin) |
| Law | a property that must hold for all inputs (round-trip, invariance), tested by generation, not examples |
| Characterization | a unit test that pins today's behavior, labeled as such; it describes, it does not bless |
| Fixture | today's shell level (`test/*.sh`): end-to-end, gates `make check`, unchanged by this quest |
| Seam | a function testable without git or processes: `fold_ledger`, `ledger_line`, `parse_edge_cycle`, kind mapping, stale gate |
| Lint rule | one machine-checkable sin, as data: id, severity, pack (ocaml \| cli), checker (command \| pattern), message. Rules are owned by `bp3 lint` (Exp 3), never prose in a skill |

## Demos

### Design trace — the seam under test (nothing here has run yet)

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
| QCheck/OUnit suite for the named seams (Exp 2 list is exhaustive) | new frameworks (no Alcotest), coverage tooling, CI changes |
| `dune test` wired into `make check` | speeding up the shell fixtures (24.6s is accepted) |
| sync of the yap-side exp shape (`red-ink`, `auto-red-ink`) if the owner wants it | yap skill edits without that nod |
| `bp3 lint` engine + OCaml/CLI rule packs (Exp 3) | other languages' packs (shell/JS ride the existing shellcheck/node checks until a pack is demanded), prose style guides, auto-fix |

## Human touchpoints

Quest approval (this file); Exp 1's exact wording in the
`quest` skill (owner reads skill diffs); promotion marking
on the icebox entry at approval.

## Exps

### Exp 1 — [Test-split standard](experiments/exp-1-test-split-standard/EXPERIMENT.md)
`/quest` gains step-level language: every exp states unit /
fixtures / demos at framing; exps may declare no unit tests
only as a justified one-liner. The exp record tables gain a
`Tests` line. Depends on: none. Lane: standard.

### Exp 2 — [Unit backfill](experiments/exp-2-unit-backfill/EXPERIMENT.md)
QCheck/OUnit suite under `src/quest/test/` for the named
seams and two laws, wired into `make check`. Two lanes:
known cases for speed, property-based for breadth.
Depends on:
Exp 1 (so its own record demonstrates the standard).
Lane: standard.

### Exp 3 — [Linters](experiments/exp-3-linters/EXPERIMENT.md)
bp3 owns its checks: a `bp3 lint` rule engine (SonarQube
shape, bp3 scale) — rules as data per language (OCaml now)
and per surface (the CLI), findings as JSON, wired into
`make check`. Prose best-practices stay out; whatever is
machine-checkable becomes a rule. Depends on: Exp 2 (its
engine seams join the unit suite). Lane: standard.

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
| Tests ossify a young seam | seam list is exhaustive and small (1,389 LOC core); characterization is labeled, so future refactors know what they're breaking |

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
| 1 | Does the test-split standard also land in the yap `red-ink`/`auto-red-ink` exp shapes, or bp3-only for now? | human |
| 2 | Is `promoted:` set on the icebox entry at this Quest's approval, per the new skill text? | human (approval does it) |
