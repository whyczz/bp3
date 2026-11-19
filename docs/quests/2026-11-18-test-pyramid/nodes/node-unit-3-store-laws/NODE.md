---
date: 2026-11-18
quest: ../../QUEST.md
node: unit.3
status: proposed
---

# unit.3 - store-laws: the fold, the schedule, the paths

## TL;DR

Unit tests for `store.ml` and `layout.ml`, the pure core of the
engine: ledger fold, ledger line encoding, legal edges, version
order, the wave scheduler, date math, icebox parsing, and Layout
paths. Table cases for known inputs, QCheck laws for invariants,
labeled characterization for today's quirks.

## Acceptance gates

Design trace (nothing has run):

```text
$ dune test
test_store: law_ledger_line_decodes_back_to_the_same_fields_it_encoded ok (200)
test_store: law_fold_ignores_event_lines_spliced_anywhere_in_a_ledger ok (200)
test_store: law_version_cmp_is_a_total_order ok (200)
test_store: law_sched_waves_place_every_dep_in_an_earlier_wave ok (200)
test_store: case_fold_walks_create_handoff_grade_land_one_prefix_at_a_time ok
test_store: case_fold_reads_a_legacy_submitted_line_as_handed_off ok
test_store: char_fold_moves_state_on_an_unknown_edge_that_carries_a_to_field ok
test_store: case_fold_reads_the_exp_era_sample_with_submitted_edges ok
test_layout: law_every_legacy_node_path_folds_to_its_canonical_id ok (200)
```

```yaml
objective: pin the store's pure core with cases, laws, and labeled characterization
prove by:
  - dune test (test/unit/test_store.ml, test/unit/test_layout.ml)   # absent today
  - one planted mutation per function family, reverted after
done when:
  - every function in the table below has at least one case_ or law_ test
  - the four laws above pass at 200 generated cases each
  - each planted mutation (fold_state_name, version_cmp, sched_waves, ledger_line) turns at least one test red
  - test_store and test_layout together run in under 1s
  - one sample per era (exp-era, graph-era, quest-era) under test/unit/samples/, sanitized (no /Users/ paths, no session ids), each pinned by a case_ test
```

## Diagram

```text
generators ─┬─ structured: ledger_line field tuples ──► round-trip law
            └─ raw text: spliced events, bad JSON, wrong types ──► fold laws + char_
fixed tables ─► case_: lifecycle prefixes, legacy spellings, version pairs, dates
samples ─────► case_: one frozen real ledger per era (exp-, graph-, quest-)
```

## Pseudocode

```python
@qcheck(ledger_fields())                 # edge from to cycle commit verdict reason
def law_ledger_line_round_trip(f):
    assert decode(Store.ledger_line(**f)) == f

@qcheck(ledger_text(), event_lines(), positions())
def law_fold_ignores_event_lines(text, events, at):
    assert Store.fold_ledger(splice(text, events, at)) == Store.fold_ledger(text)

def case_lifecycle():
    lines = [create, handoff, grade_ship, land]
    for i in range(1, len(lines) + 1):
        assert Store.fold_ledger(join(lines[:i])).state == EXPECTED[i]
```

| Function family | Kind |
|---|---|
| `fold_ledger`, `fold_edge`, `fold_state_name`, `fold_node`, `fold_quest` | law + case + char |
| `ledger_line` | law (round-trip) |
| `legal_edges` | case table: state to edges |
| `valid_slug`, `check_slug`, `canon_node_id`, `legacy_node_id` | case + law |
| `parse_version`, `version_cmp`, `version_major` | law (total order) + case |
| `sched_waves`, `sched_starved`, `dep_cycle_through`, `dep_satisfied` | law (topological) + case |
| `days_from_civil`, `ts_epoch`, `timing_of_text` | case (fixed dates) + law (monotone) |
| `parse_icebox_entry`, `icebox_matches` | case |
| `plan_knobs_from_text`, `effective_knobs` | case |
| Layout path builders and legacy lists | law (every legacy spelling folds) + case |

| Field | Value |
|---|---|
| Intent | catch fold and schedule regressions in milliseconds, with sentences for names |
| Lane | standard |
| Output | `test/unit/test_store.ml`, `test/unit/test_layout.ml`, generators module, `test/unit/samples/` |
| Acceptance | goal block above; fails today (no unit tests) |
| Depends on | unit.1 |
| Tests | known cases: lifecycle prefixes, legacy spellings, version pairs, fixed dates, and the samples; property-based: the four laws at 200 cases each; every function here is a hermetic_fn (text in, value out) |

## Prose

These functions take text or values and return values; the git
reads happen around them (`ledger_read`, `list_refs`). That is why
they can be tested without a repo, and why `g.sh`, `ready.sh` and
`diagram.sh` spend 24s proving things a fold test proves in
milliseconds.

The generator split comes from the 11-14 red-ink round 3 and is
re-decided here as adopted: structured generators own the
round-trip law, raw-text generators own the fold laws. A generator
that only emits well-formed lines would never find a parse bug.
Today's quirks (malformed JSON raises `E_INVALID_PLAN`, an unknown
edge with a `to` field still moves state) get `char_` tests: they
describe the behavior without blessing it.

The longest-copy rule in `ledger_read` reads git, but its choice
function can be extracted pure (`pick_longest : (path * text) list
-> text`). That one extraction is allowed here; any other extraction
of git-bound code parks the node back to the owner.

Samples (red-ink R8) are real node ledgers copied from the
`bp3/quest/*` storage refs, one per era; for example,
`2026-11-07-bp3-mvp-engine-core`'s exp-3-fsm ledger carries
`submitted` edges. They are sanitized and frozen under
`test/unit/samples/`, and they catch old spellings nobody thought to
generate. The 11-14 quest called them Tapes; the name changed
because a run's `tape.log` is verbatim evidence that is never
parsed.
