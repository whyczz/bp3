---
date: 2026-11-14
goal: ../../GOAL.md
exp: 1
status: proposed
---

# Exp 1 — Rendered tables for `--format table`

## TL;DR

The `"table"` branch of `print_verdict`
(`src/quest/render.ml:181`) stops dumping `k=v` lines and
renders from a **column model** per flat verdict shape:
header row, space-aligned ASCII columns, short (7-char)
commits, change counts (`+n um -d`) instead of inline JSON
lists. Quest read = one row per exp; exp read = one row per
change under a one-line summary header. JSON and `tree`
output are byte-identical to today.

## Demo (design trace)

```text
$ ./bin/bp3 q 2026-11-07-bp3-mvp-engine-core --format table
quest 2026-11-07-bp3-mvp-engine-core [proposed] rollup: landed
exp                 state    cycle  commit   changes
exp-2-cli-scaffold  landed   1      4d9ceaa  +2 u5 -1
exp-3-fsm           landed   1      4d9ceaa  +2 u5 -1

$ ./bin/bp3 q 2026-11-07-bp3-mvp-engine-core r exp-3-fsm --format table
2026-11-07-bp3-mvp-engine-core / exp-3-fsm — landed, cycle 1, commit 4d9ceaa, legal: none
change  path
u       Makefile
u       bin/bp3
+       invoke/dune
```

## Diagram

```text
verdict (Yojson) ── fmt = "table" ──► shape?
                                       ├─ quest verdict ─► exp columns
                                       ├─ exp verdict ───► change columns
                                       └─ other ─────────► today's dump (unchanged fallback)
                     fmt = json/tree ─► untouched paths
```

## Pseudocode

```python
COLUMNS = {
  "quest_exps":  [("exp", w_auto), ("state", w_auto), ("cycle", w_auto),
                  ("commit", short7), ("changes", counts)],
  "exp_changes": [("change", w_auto), ("path", w_auto)],
}

def render_table(verdict):
    rows, cols = column_model_for(verdict)   # None -> legacy dump
    widths = [max(len(header), *(len(cell(r)) for r in rows)) for cols]
    print(header_row(cols, widths))
    for r in rows: print(row(r, widths))     # plain ASCII, no box-drawing
```

## Tables

| Field | Value |
|---|---|
| Intent | `--format table` tells the truth: a table a human scans in one pass |
| Lane | standard |
| Output | new `"table"` branch in `src/quest/render.ml`; fixtures in `test/q.sh` (or its table successor) |
| Acceptance | cases below; all fail today |
| Depends on | none |

| Case | Expected after |
|---|---|
| quest read, `--format table` | header `exp state cycle commit changes`; one aligned row per exp; commit ≤7 chars; no `key=` dumps, no inline JSON |
| exp read, `--format table` | summary line + `change path` table, one row per change |
| `commit: null` / `changes: null` | `-` / `?` cells (matching tree's `short_commit` / unknown markers), never a crash |
| `--format json` (default), `--format tree` | byte-identical to pre-change output on the same quest |
| non-flat verdict under `table` | today's dump, unchanged (fallback is a decision, not a bug) |

## Acceptance test (goal block)

- **Objective:** `--format table` renders real tables for
  quest and exp reads while JSON/tree stay frozen.
- **Prove by:** run both design-trace commands against
  `2026-11-07-bp3-mvp-engine-core`; diff `--format json`
  and `--format tree` output against a pre-change capture;
  `make check` green.
- **Done when:** header rows and aligned columns appear as
  traced, the JSON/tree diff is empty, and a fixture pins
  the table shape.

## Prose

Context: born at the MVP landing, when the owner ran reads
by hand (GOAL.md, Demos/Observed). The current branch was
a placeholder that inherited the name before the rendering.
Why flat shapes only: the exp `changes` path list is a tree
wearing a list's clothes — `tree` already renders it well,
and forcing it into columns buys nothing. Edge cases:
empty exp list (header only, no rows — not an error);
`legal_edges` stays a summary-line word, never a column;
column widths come from content, so a long path widens the
table instead of truncating — a table that lies about a
path is worse than a wide one.

## Tests

unit: none (renderer is printf-shaped; no pure seam worth
extracting — justified per the test-split standard) ·
fixtures: table-shape cases in the q fixture suite, JSON/
tree byte-diff guard · demos: the two traces above, run by
hand at review
