---
status: frozen
date: 2026-11-22
promoted: null
---

# Names as constants: one file in the binary holds every spelling

## Context

Frozen 2026-11-22, in red-ink round 6 (names) of
`docs/quests/2026-11-22-induct-inline-as-default-measure-author/`.
Owner, verbatim: "btw let's make the verbs, ideas configurable in case
we want to rename", then "uhh constants in the BP3 binary, the skills
stay where they are, if we need to rename, we can rename the skills
(e.g. sed) and change the contants file?"

Renames have happened three times so far, each patched by hand:

- `graph -> quest`: `scripts/migrate-graph-rename.sh` (117 lines) and
  the retired-term sweep `scripts/check-retired-terms.sh`.
- `submit -> handoff`, `review -> grade`, `check -> verify`,
  `submitted -> handed_off`: read-side folds `Store.fold_edge` and
  `fold_state_name` (`src/quest/store.ml:172`).
- Spellings are scattered as string literals: `src/quest/main.ml` alone
  is 825 lines, and 32 distinct `E_*` codes appear across `src/quest/`.

The quest above starts `src/quest/names.ml` with only its own new
spellings (the `brief` verb, its refusal code). This entry is
everything else.

## Sketch

```text
src/quest/names.ml     every CLI door, verb, edge, state, flag and error code, one constant each
main.ml, store.ml, …   dispatch and verdicts use Names.*, never a literal
skills/, docs          plain words, untouched (no templates)
rename                 edit one constant + sed the skills/renders + add the old spelling to the read fold
                       (ledger edges, states, metric names and error codes are stored; old ledgers still read)
```

- Not added: runtime aliases, templates in skills, a names table file
  read at runtime.
- Metric names already have one home (`Metrics.registry`), and tally
  keys have `tally_json`. They stay there; `Names` points to them
  rather than copying.

## Blockers

- `Store.reserved_slugs` must be derived from `Names`, so a new verb is
  reserved automatically.
- A test must fail on a new literal verb or code outside `names.ml`.
  How strict it is (every string, or only dispatch and `err` sites) is
  undecided.
- A rename of a stored spelling still needs its fold row. Whether that
  fold lives in `Names` too (current plus retired spellings) is
  undecided.

## Promotion trigger

The next rename of any verb, edge, state or error code, or the owner
naming this entry.
