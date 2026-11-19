---
date: 2026-11-18
quest: ../../QUEST.md
node: unit.4
status: proposed
---

# unit.4 - edge-units: hooks, render, and CLI parsing

## TL;DR

Unit tests for the engine's edges: hook payload parsing, run-id
parsing, refusal codes, the hook registry's JSON round-trip, the
stale gate on a fake clock, diagram and table rendering from a fixed
rollup, and CLI flag parsing. The parameter tests the owner asked
for live here: tables of `(input, expected)` rows, one `case_` per row.

## Acceptance gates

Design trace (nothing has run):

```text
$ dune test
test_hooks: case_parse_edge_cycle_reads_handoff_and_cycle_2_from_a_run_id ok
test_hooks: law_binding_json_round_trips ok (200)
test_hooks: case_stale_gate_sweeps_a_binding_seen_901_seconds_ago ok
test_hooks: case_attempted_edge_finds_the_edge_in_a_quoted_bp3_command ok
test_render: case_emit_ascii_draws_the_fixed_three_node_rollup ok
test_main: case_parse_flags_rejects_a_flag_missing_its_value ok
```

```yaml
objective: pin hooks, render, and CLI parsing at unit speed, with table-driven cases
prove by:
  - dune test (test/unit/test_hooks.ml, test_render.ml, test_main.ml)   # absent today
  - one planted mutation per file, reverted after
done when:
  - every function in the table below has at least one case_ or law_ test
  - render golden tests compare against checked-in expected text under test/unit/golden/
  - each planted mutation (parse_edge_cycle, refusal_code, emit_ascii, split_flags) turns a test red
  - all three files run in under 1s with no process spawned
```

## Diagram

```text
hook payload JSON ─► payload_strings / command_of / attempted_edge ─► case_ tables
run_id string ─────► parse_edge_cycle ─► (edge, cycle) ─────────────► case_ table
binding ⇄ JSON ────► binding_to_json / binding_of_json ─────────────► law_ round-trip
fixed rollup JSON ─► emit_ascii / emit_mermaid / render_table_* ────► golden text
argv list ─────────► parse_flags / split_flags / normalize_verb ────► case_ tables
```

## Pseudocode

```python
PARSE_EDGE_CYCLE = [
    ("20261118T120000Z-handoff-pi-none-c2", ("handoff", 2)),          # old shape
    ("20261118T110640.123a7f3Z-handoff-pi-none-c2", ("handoff", 2)),  # seam.1 shape
    ("20261118T120000Z-grade-muse-code-opus-c1", ("grade", 1)),
    ("bare", ("", 1)),
]
for run_id, want in PARSE_EDGE_CYCLE:        # one case_ per row, named from the row
    assert Hooks.parse_edge_cycle(run_id) == want

def case_emit_ascii_draws_the_fixed_three_node_rollup():
    assert Render.emit_ascii(FIXED_ROLLUP) == read("golden/three-node.txt")
```

| Module | Functions |
|---|---|
| hooks | `parse_edge_cycle`, `attempted_edge`, `extract_preset`, `refusal_code`, `payload_strings`, `command_of`, `binding_to_json`/`binding_of_json`, stale predicate |
| render | `emit_ascii`, `emit_mermaid`, `render_table_quest`, `render_table_node`, `diagram_waves`, `short_commit`, `change_counts` |
| main | `parse_flags`, `split_flags`, `parse_dep_list`, `normalize_verb`, `is_verb`, `is_help` |
| config | `valid_index_key`, `canon_path`, `desk_matches`, `load_thresholds` (on JSON values) |

| Field | Value |
|---|---|
| Intent | test the parsing and rendering edges without launching bp3 |
| Lane | standard |
| Output | `test/unit/test_hooks.ml`, `test_render.ml`, `test_main.ml`, `golden/` |
| Acceptance | goal block above; fails today (no unit tests) |
| Depends on | unit.2 (the stale predicate needs the fake clock) |
| Tests | known cases: the case tables and golden files; property-based: `law_binding_json_round_trips`, `law_parse_edge_cycle_reads_the_cycle_from_any_generated_run_id` |

## Prose

`hooks.sh`, `completion.sh`, `mode.sh` and `config.sh` launch the
binary to check what amounts to string parsing. Those checks move
here; the fixture tier keeps one launch per door to prove the
wiring.

Golden files are checked-in expected output. When rendering changes
on purpose, the author regenerates the golden file in the same
commit and the grader reads that diff. A golden file that changes
without a matching render change is a red flag in review.

Functions that need a filesystem (`load_registry`, `save_registry`,
`list_icebox_entries`) stay at the fixture tier, and the test file
says so in a one-line comment.
